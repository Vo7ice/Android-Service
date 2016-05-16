# AlarmManagerService阅读(6.0)
- 1 介绍 
- 2 添加定时器流程
- 3 开启服务流程

## 介绍 
- `AlarmManager`类是`AlarmManagerService`的辅助类,将一些逻辑语义传递给ALMS服务器端.
- ALMS的实现代码并不算太复杂，主要只是在管理"逻辑闹钟".
- 它把逻辑闹钟分成几个大类,分别记录在不同的列表中.
- ALMS会在一个专门的线程中循环等待闹钟的激发,一旦时机到了,就"回调"逻辑闹钟对应的动作.
- ALMS在`SystemServer`中通过`startOtherServices` 注册到系统服务中.
```
mSystemServiceManager.startService(AlarmManagerService.class);
            alarm = IAlarmManager.Stub.asInterface(
                    ServiceManager.getService(Context.ALARM_SERVICE));
```
- `AlarmManager`中两个变量`WINDOW_EXACT`和`WINDOW_HEURISTIC`会根据版本不同变更,也是`windowMillis`这个参数的赋值.
- `AlarmManager`有四个常量,用来定义四种闹钟类型,区分的是时间标准和是否在睡眠状态下唤醒设备.

Type | 状态
---|---
RTC_WAKEUP  | System.currentTimeMillis(),睡眠状态可唤醒
RTC | System.currentTimeMillis(),睡眠状态不可唤醒
ELAPSED_REALTIME_WAKEUP | SystemClock.elapsedRealtime(),睡眠状态可唤醒
ELAPSED_REALTIME | SystemClock.elapsedRealtime(),睡眠状态不可唤醒


## 添加定时器流程
- client通过`(AlarmManager)context.getSystemService(Context.ALARM_SERVICE);`来获得`AlarmManager`的实例,然后调用`set`或`setExact`来设置闹钟
- 不管client调用`set`还是`setExact`,最终会调用`setImpl`方法
```
private void setImpl(int type, long triggerAtMillis, long windowMillis, long intervalMillis,
            int flags, PendingIntent operation, WorkSource workSource, AlarmClockInfo alarmClock) {
    //首先判断了触发事件triggerAtMillis,如果小于0,就赋值为0
    if (triggerAtMillis < 0) {
            triggerAtMillis = 0;
    }
    try {
            mService.set(type, triggerAtMillis, windowMillis, intervalMillis, flags, operation,
                    workSource, alarmClock);
        } catch (RemoteException ex) {
    }
```
- `mService`为`IAlarmManager`通过`binder`机制绑定了`AlarmManagerService`中的成员变量`mService`,这样就调用了`AlarmManagerService`的`set`方法,也就调用了`setImpl`方法
```
void setImpl(int type, long triggerAtTime, long windowLength, long interval,
            PendingIntent operation, int flags, WorkSource workSource,
            AlarmManager.AlarmClockInfo alarmClock, int callingUid) {
    ···
    //如果设置的时间窗口12个小时还要长，那么就将窗口设置为1个小时
    if (windowLength > AlarmManager.INTERVAL_HALF_DAY) {
            Slog.w(TAG, "Window length " + windowLength
                    + "ms suspiciously long; limiting to 1 hour");
            windowLength = AlarmManager.INTERVAL_HOUR;
    }
    //6.0新增特性 定时关机
    if (type == 7 || type == 8) {
        if (mNativeData == -1) {
            Slog.w(TAG, "alarm driver not open ,return!");
            return;
        }
        Slog.d(TAG, "alarm set type 7 8, package name " + operation.getTargetPackage());
        String packageName = operation.getTargetPackage();
    
        String setPackageName = null;
        long nowTime = System.currentTimeMillis();
        if (triggerAtTime < nowTime) {
            Slog.w(TAG, "power off alarm set time is wrong! nowTime = " + nowTime + " ; triggerAtTime = " + triggerAtTime);
            return;
        }
        synchronized (mPowerOffAlarmLock) {
            //如果已有相同的应用创建的定时关机,就将前一个移除
            removePoweroffAlarmLocked(operation.getTargetPackage());
            final int poweroffAlarmUserId = UserHandle.getCallingUserId();
            //创建一个定时关机
            Alarm alarm = new Alarm(type, triggerAtTime, 0, 0, 0,
                            interval,operation, workSource, 0, alarmClock,
                            poweroffAlarmUserId, true);
            //添加进去
            addPoweroffAlarmLocked(alarm);
            if (mPoweroffAlarms.size() > 0) {
            //确保是最近的一个注册的定时关机闹钟
            resetPoweroffAlarm(mPoweroffAlarms.get(0));
            }
        }
        type = RTC_WAKEUP;
    }
    //获取当前的elapsed时间
    final long nowElapsed = SystemClock.elapsedRealtime();
    /*
     *riggerAtTime如果是RTC制的时间话,利用这个函数转化成elapsed制的时间
     *如果本身就是elapsed制的时间,那么就不用处理直接返回将这个值设置为正常的触发时间
    */
    final long nominalTrigger = convertToElapsed(triggerAtTime, type);
    // Try to prevent spamming by making sure we aren't firing alarms in the immediate future
    //设置最短的触发时间
    final long minTrigger = nowElapsed + mConstants.MIN_FUTURITY;
    //计算触发时间,如果正常的触发时间比最小的触发时间要小,那么就要等待到最小的触发时间才能触发
    final long triggerElapsed = (nominalTrigger > minTrigger) ? nominalTrigger : minTrigger;
    //最大触发时间
    final long maxElapsed;
    //如果windowlength为0那么最大的触发时间就是triggerElapsed
    if (windowLength == AlarmManager.WINDOW_EXACT) {
                maxElapsed = triggerElapsed;
    //如果windowLength小于0的话，通过一个算法来计算这个值
    } else if (windowLength < 0) {
        maxElapsed = maxTriggerTime(nowElapsed, triggerElapsed, interval);
    //如果windowLength大于0的话那么最大触发时间为触发时间+窗口大小
    } else {
        maxElapsed = triggerElapsed + windowLength;
    }
    synchronized (mLock) {
        setImplLocked(type, triggerAtTime, triggerElapsed, windowLength, maxElapsed,
                    interval, operation, flags, true, workSource,
                    alarmClock, callingUid, mNeedGrouping);
    }
```
- 接下来就到了`setImplLocked`这个方法了.
```
/*
 *@params when : alarm触发时间有可能是rtc也有可能是elapsed的
 *@params whenElapsed : 将when转化成elapsed的触发时间
 *@params maxWhen : 将whenElapsed加上了窗口大小之后的最大触发时间
 */ 
private void setImplLocked(int type, long when, long whenElapsed, long windowLength,
            long maxWhen, long interval, PendingIntent operation, int flags,
            boolean doValidate, WorkSource workSource, AlarmManager.AlarmClockInfo alarmClock,
            int uid, boolean mNeedGrouping) {
    //创建一个闹钟实例
    Alarm a = new Alarm(type, when, whenElapsed, windowLength, maxWhen, interval,
                operation, workSource, flags, alarmClock, uid, mNeedGrouping);
    //如果这个闹钟已经排期了,就去掉原先那个
    removeLocked(operation);
    //添加闹钟
    setImplLocked(a, false, doValidate);
}
private void setImplLocked(Alarm a, boolean rebatching, boolean doValidate) {
    ···
    //如果needGrouping为false 就不用放到集合中,单独一个集合
    int whichBatch = (a.needGrouping == false)
                ? -1 : attemptCoalesceLocked(a.whenElapsed, a.maxWhenElapsed);
    /*
      如果whichBatch<0那么就意味着这个alarm没有在任何一个batch中,就新建一个batch并且将 
      isStandalone设置为true,并且加入mAlarmBatches中,加入的方式采用二分查找找到起始位置 
      比较的方式是利用batch的起始时间.即最终batchs会按照从触发时间由小到大的顺序排列.
    */
    if (whichBatch < 0) {
            Batch batch = new Batch(a);
            addBatchLocked(mAlarmBatches, batch);
    } else {
        Batch batch = mAlarmBatches.get(whichBatch);
        Slog.d(TAG, " alarm = " + a + " add to " + batch);
        if (batch.add(a)) {
            // The start time of this batch advanced, so batch ordering may
            // have just been broken.  Move it to where it now belongs.
            //因为加入了新的alarm，所以这个batch的起始时间有可能发生变化,
            //那么就需要重新安排这个batch，所以先移出队列,再重新加入到正确的位置.
            mAlarmBatches.remove(whichBatch);
            addBatchLocked(mAlarmBatches, batch);
        }
    }
    //设置驱动的定时器
    rescheduleKernelAlarmsLocked();
    //更新下一个定时器
    updateNextAlarmClockLocked();
}
```
- `rescheduleKernelAlarmsLocked`中调用`setLocked(ELAPSED_REALTIME_WAKEUP, firstWakeup.start);`,再调用了`set(mNativeData, type, alarmSeconds, alarmNanoseconds);`来设置驱动层的定时器.
- 从这里看出来设置到底层的闹钟只与类型、和触发的秒数和nano秒数有关，与其他的所有属性都没有关系。设置定时器就说完了。


