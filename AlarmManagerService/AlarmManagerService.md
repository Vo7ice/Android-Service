# AlarmManagerService阅读(6.0)
- 1 介绍 
- 2 添加定时器流程
- 3 开启服务流程
---
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
## 开启服务流程
- 七个`native`函数
    
    ```
    //打开设备驱动"/dev/alarm"返回一个long型的与fd有关的数
    private native long init();
    //关闭设备驱动
    private native void close(long nativeData);
    //设置闹钟
    private native void set(long nativeData, int type, long seconds, long nanoseconds);
    //等待闹钟激发
    private native int waitForAlarm(long nativeData);
    //设置kernel时间
    private native int setKernelTime(long nativeData, long millis);
    //设置kernel时区
    private native int setKernelTimezone(long nativeData, int minuteswest);
    //定时关机特性特有
    private native boolean bootFromAlarm(int fd);
    ```
- `onStart`函数
    
    ```
    @Override
    public void onStart() {
        //打开设备驱动"/dev/alarm"返回一个long型的与fd有关的数
        mNativeData = init();
        mNextWakeup = mNextNonWakeup = 0;
        // We have to set current TimeZone info to kernel
        // because kernel doesn't keep this after reboot
        //设置时区
        setTimeZoneImpl(SystemProperties.get(TIMEZONE_PROPERTY));
        //得到powermanager的实例  
        PowerManager pm = (PowerManager) getContext().getSystemService(Context.POWER_SERVICE);
        //得到wakelock实例，PARTIAL_WAKE_LOCK:保持CPU 运转，屏幕和键盘灯有可能是关闭的。  
        mWakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "*alarm*");
        /*
         *这个pendingintent的作用应该是系统中常用的.
         *它用来给发送一个时间改变的broadcast,intent.ACTION_TIME_TICK,每整数分钟的开始发送一次.
         *应用可以注册对应的receiver来干各种事，譬如更新时间显示等等  
         */
        mTimeTickSender = PendingIntent.getBroadcastAsUser(getContext(), 0,
                    new Intent(Intent.ACTION_TIME_TICK).addFlags(
                            Intent.FLAG_RECEIVER_REGISTERED_ONLY
                            | Intent.FLAG_RECEIVER_FOREGROUND), 0,
                            UserHandle.ALL);
        //发送一个日期改变的broadcast,每天的开始发送一次，即00:00的时候发送 
        Intent intent = new Intent(Intent.ACTION_DATE_CHANGED);
            intent.addFlags(Intent.FLAG_RECEIVER_REPLACE_PENDING);
        mDateChangeSender = PendingIntent.getBroadcastAsUser(getContext(), 0, intent,
                    Intent.FLAG_RECEIVER_REGISTERED_ONLY_BEFORE_BOOT, UserHandle.ALL);
        //注册时间和日期变更的广播接受者
        //onReceiver方法中会更新闹钟的日期
        mClockReceiver = new ClockReceiver();
        mClockReceiver.scheduleTimeTickEvent();
        mClockReceiver.scheduleDateChangedEvent();
        //注册亮屏和灭屏的广播接收者,当状态和接受到的状态不同时,就激发定时开关机闹钟
        mInteractiveStateReceiver = new InteractiveStateReceiver();
        //注册关于应用状态的广播接受者,当设置闹钟的应用重启、移除时候做的事情.
        mUninstallReceiver = new UninstallReceiver();
        //设置闹钟的应用list 内置`时钟`
        mAlarmIconPackageList = new ArrayList<String>();
        mAlarmIconPackageList.add("com.android.deskclock");
        //设备打开后就开启线程
        if (mNativeData != 0) {
            AlarmThread waitThread = new AlarmThread();
            waitThread.start();
        } else {
            Slog.w(TAG, "Failed to open alarm driver. Falling back to a handler.");
        }
        //将alarmservice注册进servicemanager  
        publishBinderService(Context.ALARM_SERVICE, mService);
    }
    ```
    - 在onstart函数中一个是有一个1分钟一个广播的定时器和00:00到了就发送的定时器,具体的1分钟一个的定时器实现就是每当1分钟到了就再设置一个一分钟的定时器
    - `publishBinderService(Context.ALARM_SERVICE, mService)`这个函数做的事是将一个binder对象注册进了ServiceManager
    -  `AlarmManagerService.java  AlarmThrea内部类`,闹钟的激发、传递、排期都是由这个线程决定的.
- `AlarmThrea` 的`run`方法
    
    **run示意图**

    ![run] (https://raw.githubusercontent.com/Vo7ice/Android-Service/master/3.png)
    ```
    public void run()
    {
        ArrayList<Alarm> triggerList = new ArrayList<Alarm>();

        while (true)
        {
            //等待一个底层的RTC闹钟的触发，这个过程应该是同步阻塞的(ioctl) 
            int result = waitForAlarm(mNativeData);

            triggerList.clear();

            final long nowRTC = System.currentTimeMillis();
            final long nowELAPSED = SystemClock.elapsedRealtime();
            if ((result & TIME_CHANGED_MASK) != 0) {
                // The kernel can give us spurious time change notifications due to
                // small adjustments it makes internally; we want to filter those out.
                //内核会因为小调整而给出需要假的事件更改通知,我们将这些剔除掉
                final long lastTimeChangeClockTime;
                final long expectedClockTime;
                synchronized (mLock) {
                    lastTimeChangeClockTime = mLastTimeChangeClockTime;
                    expectedClockTime = lastTimeChangeClockTime
                            + (nowELAPSED - mLastTimeChangeRealtime);
                }
                if (lastTimeChangeClockTime == 0 || nowRTC < (expectedClockTime-500)
                            || nowRTC > (expectedClockTime+500)) {
                    // The change is by at least +/- 500 ms (or this is the first change),
                    // let's do it!
                    //当变化>=500ms或第一次时才进行调整时间
                    if (DEBUG_BATCH) {
                        Slog.v(TAG, "Time changed notification from kernel; rebatching");
                    }
                    removeImpl(mTimeTickSender);
                    rebatchAllAlarms();
                    //重新设置scheduletimetickevent这个pendingintent了
                    mClockReceiver.scheduleTimeTickEvent();
                    synchronized (mLock) {
                        mNumTimeChanged++;
                        mLastTimeChangeClockTime = nowRTC;
                        mLastTimeChangeRealtime = nowELAPSED;
                    }
                    Intent intent = new Intent(Intent.ACTION_TIME_CHANGED);
                    intent.addFlags(Intent.FLAG_RECEIVER_REPLACE_PENDING
                                | Intent.FLAG_RECEIVER_REGISTERED_ONLY_BEFORE_BOOT);
                    getContext().sendBroadcastAsUser(intent, UserHandle.ALL);
                    // The world has changed on us, so we need to re-evaluate alarms
                    // regardless of whether the kernel has told us one went off.
                    result |= IS_WAKEUP_MASK;
                }
            }
            if (result != TIME_CHANGED_MASK) {    
                // If this was anything besides just a time change, then figure what if
                // anything to do about alarms.
                synchronized (mLock) {
                    if (localLOGV) Slog.v(
                        TAG, "Checking for alarms... rtc=" + nowRTC
                        + ", elapsed=" + nowELAPSED);
                    ...
                    boolean hasWakeup = triggerAlarmsLocked(triggerList, nowELAPSED, nowRTC);
                    if (!hasWakeup && checkAllowNonWakeupDelayLocked(nowELAPSED)) {
                        // if there are no wakeup alarms and the screen is off, we can
                        // delay what we have so far until the future.
                        //如果没有唤醒屏幕的定时器且屏幕是灭屏状态,我们可以延迟定时器
                        if (mPendingNonWakeupAlarms.size() == 0) {
                            mStartCurrentDelayTime = nowELAPSED;
                            mNextNonWakeupDeliveryTime = nowELAPSED
                                    + ((currentNonWakeupFuzzLocked(nowELAPSED)*3)/2);
                        }
                        mPendingNonWakeupAlarms.addAll(triggerList);
                        mNumDelayedAlarms += triggerList.size();
                        //重新安排定时器
                        rescheduleKernelAlarmsLocked();
                        updateNextAlarmClockLocked();
                    } else {
                        //现在可以传递定时器意图了,如果有后续的不唤醒定时器,我们需要将它们放到一个集合中.
                        //我们并没有一开始就发送它们,因为我们想要将非唤醒定时器在唤醒定时器发送完后再发送
                        rescheduleKernelAlarmsLocked();
                        updateNextAlarmClockLocked();
                        //判断非唤醒定时器容器大小
                        if (mPendingNonWakeupAlarms.size() > 0) {
                            calculateDeliveryPriorities(mPendingNonWakeupAlarms);
                            triggerList.addAll(mPendingNonWakeupAlarms);
                            Collections.sort(triggerList, mAlarmDispatchComparator);
                            final long thisDelayTime = nowELAPSED - mStartCurrentDelayTime;
                            mTotalDelayTime += thisDelayTime;
                            if (mMaxDelayTime < thisDelayTime) {
                                mMaxDelayTime = thisDelayTime;
                            }
                            mPendingNonWakeupAlarms.clear();
                        }
                        //传递定时器意图
                        deliverAlarmsLocked(triggerList, nowELAPSED);
                    }
                }
            }
        }
    }
    ```
    - 重要函数一:`triggerAlarmsLocked(triggerList, nowELAPSED, nowRTC);`
        
        ```
        boolean triggerAlarmsLocked(ArrayList<Alarm> triggerList, final long nowELAPSED,
            final long nowRTC) {
            boolean hasWakeup = false;
            while (mAlarmBatches.size() > 0) {
                Batch batch = mAlarmBatches.get(0);
                //如果第0个batch的开始时间比现在的时间还大.
                //说明现在没有合适的定时器需要触发,跳出循环 
                if (batch.start > nowELAPSED) {
                    break;
                }
                //防止影响传递
                mAlarmBatches.remove(0);
                final int N = batch.size();
                for (int i = 0; i < N; i++) {
                    Alarm alarm = batch.get(i);
                    //当存在ALLOW_WHILE_IDLE定时器,我们要约束这个应用的间隔
                    if ((alarm.flags&AlarmManager.FLAG_ALLOW_WHILE_IDLE) != 0) {
                        long lastTime = mLastAllowWhileIdleDispatch.get(alarm.uid, 0);
                        long minTime = lastTime + mAllowWhileIdleMinTime;
                        if (nowELAPSED < minTime) {
                            //间隔不够,需要重新排期到正确的时间段
                            alarm.whenElapsed = minTime;
                            if (alarm.maxWhenElapsed < minTime) {
                                alarm.maxWhenElapsed = minTime;
                            }
                            setImplLocked(alarm, true, false);
                            continue;
                        }
                    }
                    alarm.count = 1;
                    //添加到集合中
                    triggerList.add(alarm);
                    //重置一些对象
                    if (mPendingIdleUntil == alarm) {
                        mPendingIdleUntil = null;
                        rebatchAllAlarmsLocked(false);
                        restorePendingWhileIdleAlarmsLocked();
                    }
                    if (mNextWakeFromIdle == alarm) {
                        mNextWakeFromIdle = null;
                        rebatchAllAlarmsLocked(false);
                    }
                    // 如果这个定时器是重复性定时器,那么就进入循环 
                    //首先计算它的count值,这个值是用来计算到下次触发说要经过的时间间隔数. 
                    //从而可以计算出下次激发时间，然后将这个重复闹钟重新设置到定时器batch中去
                    if (alarm.repeatInterval > 0) {
                        //如果我们没有延迟一个周期以上的话 count会变为0
                        alarm.count += (nowELAPSED - alarm.whenElapsed) / alarm.repeatInterval;
                        final long delta = alarm.count * alarm.repeatInterval;
                        final long nextElapsed = alarm.whenElapsed + delta;
                        final long maxElapsed = maxTriggerTime(nowELAPSED, nextElapsed, alarm.repeatInterval);
                        alarm.needGrouping = true;
                        setImplLocked(alarm.type, alarm.when + delta, nextElapsed, alarm.windowLength,
                            maxElapsed,
                            alarm.repeatInterval, alarm.operation, alarm.flags, true,
                            alarm.workSource, alarm.alarmClock, alarm.uid, alarm.needGrouping);
                    }
                    //如果是可以唤醒屏幕的定时器,就设置为true
                    if (alarm.wakeup) {
                        hasWakeup = true;
                    }
                    //我们去掉了一个定时器,让程序再安排一个新的定时器
                    if (alarm.alarmClock != null) {
                        mNextAlarmClockMayChange = true;
                    }
                }
            }
        }
        ```
        `triggerAlarmsLocked`做的就是将符合激发条件的定时器移到`AlarmThread`临时创建的`triggerList`中
    - 重要函数二:`deliverAlarmsLocked(triggerList, nowELAPSED);`
        
        ```
        void deliverAlarmsLocked(ArrayList<Alarm> triggerList, long nowELAPSED) {
            mLastAlarmDeliveryTime = nowELAPSED;
            final long nowRTC = System.currentTimeMillis();
            boolean needRebatch = false;
            //遍历数组
            for (int i=0; i<triggerList.size(); i++) {
                //获得Alarm实例
                Alarm alarm = triggerList.get(i);
                //判断是否是ALLOW_WHILE_IDLE定时器
                final boolean allowWhileIdle = (alarm.flags&AlarmManager.FLAG_ALLOW_WHILE_IDLE) != 0;
                //定时开关机特性
                updatePoweroffAlarm(nowRTC);
                try {
                    //先将定时器打开
                    if (RECORD_ALARMS_IN_HISTORY) {
                    if (alarm.workSource != null && alarm.workSource.size() > 0) {
                        for (int wi=0; wi<alarm.workSource.size(); wi++) {
                            ActivityManagerNative.noteAlarmStart(
                                    alarm.operation, alarm.workSource.get(wi), alarm.tag);
                        }
                    } else {
                        ActivityManagerNative.noteAlarmStart(
                                alarm.operation, -1, alarm.tag);
                    }
                }
                alarm.operation.send(getContext(), 0,
                        mBackgroundIntent.putExtra(
                                Intent.EXTRA_ALARM_COUNT, alarm.count),
                        mResultReceiver, mHandler, null, allowWhileIdle ? mIdleOptions : null);
                // we have an active broadcast so stay awake.
                if (mBroadcastRefCount == 0) {
                    setWakelockWorkSource(alarm.operation, alarm.workSource,
                            alarm.type, alarm.tag, true);
                    mWakeLock.acquire();
                }
                //保存了pendingIntent的状态、pkg、uid
                final InFlight inflight = new InFlight(AlarmManagerService.this,
                        alarm.operation, alarm.workSource, alarm.type, alarm.tag, nowELAPSED);
                mInFlight.add(inflight);
                mBroadcastRefCount++;
                if (allowWhileIdle) {
                    // 记录下最后一次的ALLOW_WHILE_IDLE的定时器事件
                    mLastAllowWhileIdleDispatch.put(alarm.uid, nowELAPSED);
                }
                final BroadcastStats bs = inflight.mBroadcastStats;
                bs.count++;
                if (bs.nesting == 0) {
                    bs.nesting = 1;
                    bs.startTime = nowELAPSED;
                } else {
                    bs.nesting++;
                }
                final FilterStats fs = inflight.mFilterStats;
                fs.count++;
                if (fs.nesting == 0) {
                    fs.nesting = 1;
                    fs.startTime = nowELAPSED;
                } else {
                    fs.nesting++;
                }
                //判断了闹钟的类型,激活闹钟
                if (alarm.type == ELAPSED_REALTIME_WAKEUP
                        || alarm.type == RTC_WAKEUP) {
                    bs.numWakeup++;
                    fs.numWakeup++;
                    if (alarm.workSource != null && alarm.workSource.size() > 0) {
                        for (int wi=0; wi<alarm.workSource.size(); wi++) {
                            ActivityManagerNative.noteWakeupAlarm(
                                    alarm.operation, alarm.workSource.get(wi),
                                    alarm.workSource.getName(wi), alarm.tag);
                        }
                    } else {
                        ActivityManagerNative.noteWakeupAlarm(
                                alarm.operation, -1, null, alarm.tag);
                    }
                }
            } catch (PendingIntent.CanceledException e) {
                if (alarm.repeatInterval > 0) {
                    // This IntentSender is no longer valid, but this
                    // is a repeating alarm, so toss the hoser.
                    needRebatch = removeInvalidAlarmLocked(alarm.operation) || needRebatch;
                } catch (RuntimeException e) {
                Slog.w(TAG, "Failure sending alarm.", e);
                }
            }
            if (needRebatch) {
                Slog.v(TAG, " deliverAlarmsLocked removeInvalidAlarmLocked then rebatch ");
                rebatchAllAlarmsLocked(true);
                rescheduleKernelAlarmsLocked();
                updateNextAlarmClockLocked();
            }
        }
        ```
        遍历每一个`Alarm`对象,就执行它的`alarm.operation.send()`,`alarm`中记录的`operation`就是设置的时候传来的`PendingIntent`,也就是执行了`PendingIntent`的`send()`方法.
        
        ```
        public void send(Context context, int code, @Nullable Intent intent,
            @Nullable OnFinished onFinished, @Nullable Handler handler,
            @Nullable String requiredPermission)
            throws CanceledException {
            send(context, code, intent, onFinished, handler, requiredPermission, null);
        }
        ```
        调用了下面的`send()`函数
        
        ```
        public void send(Context context, int code, @Nullable Intent intent,
            @Nullable OnFinished onFinished, @Nullable Handler handler,
            @Nullable String requiredPermission, @Nullable Bundle options)
            throws CanceledException {
            try {
                String resolvedType = intent != null ?
                        intent.resolveTypeIfNeeded(context.getContentResolver())
                        : null;
                int res = mTarget.send(code, intent, resolvedType,
                    onFinished != null
                            ? new FinishedDispatcher(this, onFinished, handler)
                            : null,
                    requiredPermission, options);
                if (res < 0) {
                    throw new CanceledException();
                }
            } catch (RemoteException e) {
                throw new CanceledException(e);
            }
        }
        ```
        `mTarget`是个`IPendingIntent`代理接口，它对应AMS(`Activity Manager Service`)中的某个`PendingIntentRecord实体`.需要说明的是,`PendingIntent`的重要信息都是在AMS的`PendingIntentRecord`以及`PendingIntentRecord.Key`对象中管理的.AMS中有一张哈希表专门用于记录所有可用的`PendingIntentRecord`对象.
        
        **哈希表** 
        
        ![hashTable] (https://raw.githubusercontent.com/Vo7ice/Android-Service/master/2.png)
        
        接下来就是唤醒闹钟的事情了.
        
        ```
        if (alarm.type == ELAPSED_REALTIME_WAKEUP
                        || alarm.type == RTC_WAKEUP) {
            bs.numWakeup++;
            fs.numWakeup++;
            if (alarm.workSource != null && alarm.workSource.size() > 0) {
                for (int wi=0; wi<alarm.workSource.size(); wi++) {
                    ActivityManagerNative.noteWakeupAlarm(
                            alarm.operation, alarm.workSource.get(wi),
                            alarm.workSource.getName(wi), alarm.tag);
                }
            } else {
                ActivityManagerNative.noteWakeupAlarm(
                            alarm.operation, -1, null, alarm.tag);
            }
        }
        ```
        - 这两种`alarm`就是我们常说的0型和2型闹钟,它们和我们手机的续航时间息息相关.
        - AMS里的`noteWakeupAlarm()`比较简单,只是在调用`BatteryStatsService`服务的相关动作,但是却会导致机器的唤醒.
        
        ```
        public void noteAlarmStart(IIntentSender sender, int sourceUid, String tag) {
            if (!(sender instanceof PendingIntentRecord)) {
                return;
            }
            final PendingIntentRecord rec = (PendingIntentRecord)sender;
            final BatteryStatsImpl stats = mBatteryStatsService.getActiveStatistics();
            synchronized (stats) {
                mBatteryStatsService.enforceCallingPermission();
                int MY_UID = Binder.getCallingUid();
                int uid = rec.uid == MY_UID ? Process.SYSTEM_UID : rec.uid;
                mBatteryStatsService.noteAlarmStart(tag, sourceUid >= 0 ? sourceUid : uid);
            }
        }
        ```
        **总结**
        
        ![image](https://raw.githubusercontent.com/Vo7ice/Android-Service/master/1.png)
        
- `mBroadcastRefCount`的用法
    ```
    for (int i=0; i<triggerList.size(); i++) {
        Alarm alarm = triggerList.get(i);          ...
        // we have an active broadcast so stay awake.
        if (mBroadcastRefCount == 0) {
            setWakelockWorkSource(alarm.operation, alarm.workSource,
                    alarm.type, alarm.tag, true);
            mWakeLock.acquire();
        }
        final InFlight inflight = new InFlight(AlarmManagerService.this,
                alarm.operation, alarm.workSource, alarm.type, alarm.tag, nowELAPSED);
        mInFlight.add(inflight);
        mBroadcastRefCount++;
        ...
    ```
    在遍历的时候,当有可激发的`alarm`时,`mBroadcastRefCount`会累加,一开始`mBroadcastRefCount`为0会执行`if`语句,会调用`mWakeLock.acquire()`获得屏幕锁.
    
    这个变量`mBroadcastRefCount`其实是决定何时`mWakeLock`的计数器,`AlarmThread`决定了,只要还有可激发的`alarm`,机器就不能完全睡眠.
    
    释放这个`mWakeLock`就在`alarm.operation.send()`中的`mResultReceiver`参数中
    `mResultReceiver`是`AlarmManagerService`的私有变量:
    
    `final ResultReceiver mResultReceiver = new ResultReceiver();`
    
    类型为`ResultReceiver`,实现了`PendingIntent.OnFinished`接口
    
    `class ResultReceiver implements PendingIntent.OnFinished`
    
    当`send`函数结束后,框架会间接回调这个对象的`onSendFinished()`方法
    
    ```
    public void onSendFinished(PendingIntent pi, Intent intent, int resultCode,
            String resultData, Bundle resultExtras) {
        .....
        for (int i=0; i<mInFlight.size(); i++) {
            if (mInFlight.get(i).mPendingIntent == pi) {
            inflight = mInFlight.remove(i);
                break;
            }
        }
        mBroadcastRefCount--;
        if (mBroadcastRefCount == 0) {
            mWakeLock.release();
        }
        .....
    ```
    每当处理完一个`alarm`的`send()`动作,mBroadcastRefCount`就会减一，一旦减为0，就释放`mWakeLock`.
    
    



