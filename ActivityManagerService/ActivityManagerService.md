# ActivityManagerService

## 注册
SystemServer中:
  在`SystemServer`中的`run`方法中的`startBootstrapServices`时候,通过继承自`SystemService`的内部类`LifeCycle`来获得`ActivityManagerService`的对象,然后设置了`SystemServiceManager`和`Installer`变量来管理生命周期和安装`Apk`.

### 构造方法
1. 通过参数获得上下文
2. 是否为工厂模式
3. 获得当前`ActivityThread`进程
4. 初始化`MainHandler`和`UiHandler`
5. 注册两个广播队列:前台和普通
6. 初始化`ActiveServices`
7. 初始化系统文件夹
8. 初始化系统服务 /data和/data/system
    Service | 文件路径 | 描述
    ---|---|---
    BatteryStatsService | /data/system/batterystats.bin | 管理电池使用状态
    ProcessStatsService | /data/system/procstats | 管理进程状态
    UsageStatsService | /data/system/usagestats | 管理用户使用状态
    AppOpsService | /data/system/appops.xml | 管理权限控制
    AtomicFile | /data/system/urigrants.xml | 管理系统URI权限
9. 初始化`Configuration`
10. 获取`OpenGL`版本
11. 初始化`mProcessCpuTracker`,用来统计CPU、内存等信息.其内部工作原理就是读取并解析`/proc/stat`文件的内容.该文件由内核生成,用于记录`kernel`及`system`一些运行时的统计信息。读者可在Linux系统上通过`man proc`命令查询详细信息
12. 初始化`mCompatModePackages`,用来解析`/data/system/packages-compat.xml`,存储了那些需要考虑屏幕尺寸的`APK`
13. 初始化`mIntentFirewall`
14. 初始化`mRecentTasks`,用来保存近期打开的activity
15. 初始化`mStackSupervisor`,用来管理所有的`ActivityStacks`
16. 初始化`mTaskPersister`,用来开机回复`Task`
17. 初始化`mProcessCpuThread`,用来定时更新系统信息
18. 加载`WatchDog`看门狗
19. 是否支持`MultiWindowProxy`多屏协作

### `start`函数
- 重启`ActivityManagerService`时清除所有`process`
- 开启`mProcessCpuThread`.
- 发布一些服务(电池状态,权限管理,本地服务,ANR管理)
- 动态处理`AMS`的`Log`

### `ActivityThread`分析
在`SystemServer`中通过`createSystemContext`初始化系统进程的上下文.
在`Android6.0`中,将`ActivityThread`和`ActivityManagerService`解耦出去了.
`ActivityThread`是`Android Framework`中一个非常重要的类,它代表一个应用进程的主线程(对于应用进程来说，`ActivityThread`的`main`函数确实是由该进程的主线程执行),其职责就是调度及执行在该线程中运行的四大组件.
- `systemMain`函数
  
  ```Java
  public static ActivityThread systemMain() {
    //因为硬件加速渲染会增加进程的内存消耗,
    //系统进程system_process在低内存状态下不用硬件加速渲染技术
    if (!ActivityManager.isHighEndGfx()) {
            HardwareRenderer.disable(true);
        } else {
            HardwareRenderer.enableForegroundTrimming();
        }
        //创建一个对象
        ActivityThread thread = new ActivityThread();
        thread.attach(true);
        return thread;
    }
  ```
  在这里,`SystemServer`对应的`ActivityThread`对象是可以看作是运行`framework-res.apk`的进程.
- `getSystemContext`函数
    
    ```Java
    public ContextImpl getSystemContext() {
        synchronized (this) {
            //初始化一个LoadedApk对象和ContextImpl对象
            if (mSystemContext == null) {//单例模式
                mSystemContext = ContextImpl.createSystemContext(this);
            }
            return mSystemContext;
        }
    }
    ```
    这个函数调用了`ContextImpl`中的`createSystemContext(ActivityThread mainThread)`
    
    ```Java
    static ContextImpl createSystemContext(ActivityThread mainThread) {
        //LoadedApk代表一个加载到系统中的APK
        LoadedApk packageInfo = new LoadedApk(mainThread);
        //初始化该ContextImpl对象
        ContextImpl context = new ContextImpl(null, mainThread,
                packageInfo, null, null, false, null, null, Display.INVALID_DISPLAY);
        //初始化资源信息
        context.mResources.updateConfiguration(context.mResourcesManager.getConfiguration(),
                context.mResourcesManager.getDisplayMetricsLocked());
        return context;
    }
    ```
- `attach`函数
    
    ```Java
    private void attach(boolean system) {
        sCurrentActivityThread = this;//当前进程
        mSystemThread = system;//判断是否为系统进程
        if (!system) {
            ...//应用程序处理流程
        } else {
            //设置进程名字为"system_process"
            android.ddm.DdmHandleAppName.setAppName("system_process",
                    UserHandle.myUserId());
            try {
                mInstrumentation = new Instrumentation();
                //初始化ContextImpl对象
                ContextImpl context = ContextImpl.createAppContext(
                        this, getSystemContext().mPackageInfo);
                //在LoadedApk中利用Instrumentation创建一个Application对象,第二参数为null,没有执行onCreate方法
                mInitialApplication = context.mPackageInfo.makeApplication(true, null);
                //将onCreate单独置于外部
                mInitialApplication.onCreate();
            } catch (Exception e) {
                throw new RuntimeException(
                        "Unable to instantiate Application():" + e.toString(), e);
            }
        }
        //加入dropbox日志记录到核心库中
        DropBox.setReporter(new DropBoxReporter());
        ViewRootImpl.addConfigCallback(new ComponentCallbacks2() {
            @Override
            public void onConfigurationChanged(Configuration newConfig) {
                synchronized (mResourcesManager) {
                    //当系统配置发生变化（如语言切换等）时，需要调用该回调
                    ...
                }
            }
            @Override
            public void onLowMemory() {
            }
            @Override
            public void onTrimMemory(int level) {
            }
        });
    }
    ```
    在`attach`函数中`makeApplication`是调用了`LoadedApk`中的,代码如下:
    
    ```Java
    public Application makeApplication(boolean forceDefaultAppClass,
            Instrumentation instrumentation) {
        if (mApplication != null) {
            return mApplication;
        }

        Application app = null;

        String appClass = mApplicationInfo.className;//如果是system_process为空
        if (forceDefaultAppClass || (appClass == null)) {
            appClass = "android.app.Application";//重新赋值
        }
        try {
            java.lang.ClassLoader cl = getClassLoader();
            if (!mPackageName.equals("android")) {//system_process为"android"
                initializeJavaContextClassLoader();
            }
            ContextImpl appContext = ContextImpl.createAppContext(mActivityThread, this);
            //创建Application对象
            app = mActivityThread.mInstrumentation.newApplication(
                    cl, appClass, appContext);
            appContext.setOuterContext(app);
        } catch (Exception e) {
            if (!mActivityThread.mInstrumentation.onException(app, e)) {
                throw new RuntimeException(
                    "Unable to instantiate application " + appClass
                    + ": " + e.toString(), e);
            }
        }
        //将对象放进集合中
        mActivityThread.mAllApplications.add(app);
        //记录当前Application
        mApplication = app;
        //是否调用onCreate
        if (instrumentation != null) {
            try {
                instrumentation.callApplicationOnCreate(app);
            } catch (Exception e) {
                if (!instrumentation.onException(app, e)) {
                    throw new RuntimeException(
                        "Unable to create application " + app.getClass().getName()
                        + ": " + e.toString(), e);
                }
            }
        }
        ...//重写资源文件
    }
    ```
    这里用到了几个很重要的类,`Instrumentation`,`Application`,`Context`.
    - `Instrumentation`:`Instrumentation`类是一个工具类.当它被启用时,系统先创建它,再通过它来创建其他组件.另外,系统和组件之间的交互也将通过`Instrumentation`来传递.这样,`Instrumentation`就能监测系统和这些组件的交互情况了.
    - `Application`:`Application`类保存了一个全局的`application`状态.`Application`由`AndroidManifest.xml`中的`<application>`标签声明.在实际使用时需定义`Application`的派生类.
    - `Context`:`Context`是一个接口,通过它可以获取并操作`Application`对应的资源,类,甚至包含于`Application`中的四大组件.
    - `ContextImpl`:为`Context`的常用实现类.

### 初始化总结
初始化目的有两个:
 - 初始化了`AMS`对象
 - 创建一个供`SystemServer`进程使用的`Android`运行环境,`Android`运行环境将包括两个成员：`ActivityThread`和`ContextImpl`.

### `AMS`的`setSystemProcess`分析
- `setSystemProcess`是为了`System_process`系统进程做准备並开启它.`// Set up the Application instance for the system process and get started.`
- 这个函数主要做了这么几件事:
  - 向`ServiceManager`注册几个服务
    
    ```Java
    //注册自己,并允许隔离沙箱进程能访问自身
    ServiceManager.addService(Context.ACTIVITY_SERVICE, this, true);
    //注册管理进程状态
    ServiceManager.addService(ProcessStats.SERVICE_NAME, mProcessStats);
    //用于打印应用进程使用内存的信息
    ServiceManager.addService("meminfo", new MemBinder(this));
    //用于打印应用进程使用硬件显示加速方面的信息
    ServiceManager.addService("gfxinfo", new GraphicsBinder(this));
    //用于打印应用进程的使用数据库的信息
    ServiceManager.addService("dbinfo", new DbBinder(this));
    //用于打印应用进程的使用cpu的信息
    if (MONITOR_CPU_USAGE) {//默认为true
        ServiceManager.addService("cpuinfo", new CpuBinder(this));
    }
    //注册权限管理服务
    ServiceManager.addService("permission", new PermissionController(this));
    //注册进程信息服务
    ServiceManager.addService("processinfo", new ProcessInfoService(this));
    //注册ANR服务(mediatek注册)
    ServiceManager.addService("anrmanager", mANRManager, true);
    ```
  - 向`PackageManagerService`查询`package`名为`"android"`的`ApplicationInfo`.
    ```Java
    ApplicationInfo info = mContext.getPackageManager().getApplicationInfo(
                    "android", STOCK_PM_FLAGS);
    ```
    `Android`希望`SystemServer`中的服务也通过`Android`运行环境来交互.这更多是从设计上来考虑的,比如组件之间交互接口的统一及未来系统的可扩展性.
  - 调用`ActivityThread`的`installSystemApplicationInfo`函数
    
    ```Java
    mSystemThread.installSystemApplicationInfo(info, getClass().getClassLoader());
    ```
    `ActivityThread`的`installSystemApplicationInfo`
    ```Java
    public void installSystemApplicationInfo(ApplicationInfo info, ClassLoader classLoader) {
        synchronized (this) {
            //将之前的ContextImpl对象调用installSystemApplicationInfo方法
            getSystemContext().installSystemApplicationInfo(info, classLoader);

            // give ourselves a default profiler
            //创建一个Profiler对象，用于性能统计
            mProfiler = new Profiler();
        }
    }
    ```
    `ContextImpl`的`installSystemApplicationInfo`
    
    ```Java
    void installSystemApplicationInfo(ApplicationInfo info, ClassLoader classLoader) {
        //调用LoadedApk对象的installSystemApplicationInfo方法
        mPackageInfo.installSystemApplicationInfo(info, classLoader);
    }
    ```
    `LoadedApk`的`installSystemApplicationInfo`
    ```Java
    /**
     * Sets application info about the system package.
     */
    void installSystemApplicationInfo(ApplicationInfo info, ClassLoader classLoader) {
        //断言为系统进程system_process
        assert info.packageName.equals("android");
        //给进程赋值
        mApplicationInfo = info;
        mClassLoader = classLoader;
    }
    ```
    上面所做的调用只有一个目的,为之前创建的`ContextImpl`绑定`ApplicationInfo`.因为`framework-res.apk`运行在`SystemServer`中.和其他所有`apk`一样,它的运行需要一个正确初始化的`Android`运行环境.
  - 创建系统进程的`ProcessRecord`
    
    ```Java
    synchronized (this) {
        //Android进程管理
        ProcessRecord app = newProcessRecordLocked(info, info.processName, false, 0);
        //常驻内存
        app.persistent = true;
        //进程号
        app.pid = MY_PID;
        //内存管理优先级 -16:System_process默认
        app.maxAdj = ProcessList.SYSTEM_ADJ;
        //设置ActivityThread,跟踪进程状态
        app.makeActive(mSystemThread.getApplicationThread(), mProcessStats);
        synchronized (mPidsSelfLocked) {
            //保存该ProcessRecord对象
            mPidsSelfLocked.put(app.pid, app);
        }
        //根据系统当前状态,更新进程调度优先级
        updateLruProcessLocked(app, false, null);
        //内存管理
        updateOomAdjLocked();
    ```
    
    `ActivityManagerService`的`newProcessRecordLocked`
    
    ```Java
    final ProcessRecord newProcessRecordLocked(ApplicationInfo info, String customProcess,
            boolean isolated, int isolatedUid) {
        //进程名字
        String proc = customProcess != null ? customProcess : info.processName;
        //电量状态服务
        BatteryStatsImpl stats = mBatteryStatsService.getActiveStatistics();
        //判断用户
        final int userId = UserHandle.getUserId(info.uid);
        //uid
        int uid = info.uid;
        if (isolated) {
            ...//处理是隔离进程情况
        }
        //创建对象
        final ProcessRecord r = new ProcessRecord(stats, info, proc, uid);
        //判断是否需要常驻后台
        if (!mBooted && !mBooting
                && userId == UserHandle.USER_OWNER
                && (info.flags & PERSISTENT_MASK) == PERSISTENT_MASK) {
            r.persistent = true;
        }
        //添加到集合中,並排除同名的进程.
        addProcessNameLocked(r);
        return r;
    }
    ```
    `ProcessRecord`类的构造函数
    
    ```Java
    ProcessRecord(BatteryStatsImpl _batteryStats, ApplicationInfo _info,
            String _processName, int _uid) {
        mBatteryStats = _batteryStats;//电量统计服务
        info = _info;//保存ApplicationInfo
        isolated = _info.uid != _uid;//是否为隔离进程
        uid = _uid;//进程的用户id
        userId = UserHandle.getUserId(_uid);//进程的用户
        processName = _processName;//进程名字
        //一个进程能运行多个Package，pkgList用于保存package名
        pkgList.put(_info.packageName, new ProcessStats.ProcessStateHolder(_info.versionCode));
        //最大内存管理等级,默认为16
        maxAdj = ProcessList.UNKNOWN_ADJ;
        //进程最近或当前不限制管理的等级
        curRawAdj = setRawAdj = -100;
        //进程最近或当前管理的等级
        curAdj = setAdj = -100;
        //是否为常驻内存的进程
        persistent = false;
        //安装包有没有删除
        removed = false;
        //记录状态改变,上次请求和恢复内存情况的时间
        lastStateTime = lastPssTime = nextPssTime = SystemClock.uptimeMillis();
        /// M: BMW. Whether this process AP is in max/restore status
        inMaxOrRestore = false;
    }
    ```
    - `ProcessRecord`保存了耗电情况,`ApplicationInfo`,进程名字,进程用户号.一个进程虽然可运行多个`Application`,但是`ProcessRecord`一般保存该进程中先运行的那个`Application`的`ApplicationInfo`.
    - 作为`SystemServer`的进程,会将这个对象的值设置为特定的值.
       
       ```Java
       //设置为常驻内存
       app.persistent = true;
       //设置进程号
       app.pid = MY_PID;
       //设置为系统默认内存管理等级
       app.maxAdj = ProcessList.SYSTEM_ADJ;
       //设置ActivityThread和状态管理
       app.makeActive(mSystemThread.getApplicationThread(), mProcessStats);
       ```

### `setSystemProcess`总结:
- 注册`AMS`,`meminfo`,`gfxinfo`等服务到`ServiceManager`中.
- 根据PKMS返回的`ApplicationInfo`初始化`Android`运行环境,并创建一个代表`SystemServer`进程的`ProcessRecord`,从此,`SystemServer`进程也并入AMS的管理范围内.
    



    
