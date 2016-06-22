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

## `SettingsProvider`运行过程
在`SystemServer`中通过`mActivityManagerService.installSystemProviders();`来将`SettingsProvider.apk`加载进系统进程中.

###  `installSystemProviders`函数

```Java
public final void installSystemProviders() {
    List<ProviderInfo> providers;
        synchronized (this) {
            /*
             * 从集合mProcessNames中找到进程名字为"system",且uid为SYSTEM_UID的ProcessRecord
             * 也就是之前创建的那个SystemServer进程
             */
            ProcessRecord app = mProcessNames.get("system", Process.SYSTEM_UID);
            //重要函数
            providers = generateApplicationProvidersLocked(app);
            if (providers != null) {
                for (int i=providers.size()-1; i>=0; i--) {
                    //将非系统APK提供的Provider删除,通过flag
                    ProviderInfo pi = (ProviderInfo)providers.get(i);
                    if ((pi.applicationInfo.flags&ApplicationInfo.FLAG_SYSTEM) == 0) {
                        Slog.w(TAG, "Not installing system proc provider " + pi.name
                                + ": not system .apk");
                        providers.remove(i);
                    }
                }
            }
        }
        //为SystemServer进程安装Provider
        if (providers != null) {
            mSystemThread.installSystemProviders(providers);
        }
        //监视Settings数据库中表的变化.
        //现在有LONG_PRESS_TIMEOUT,TIME_12_24,DEBUG_VIEW_ATTRIBUTES三个配置
        mCoreSettingsObserver = new CoreSettingsObserver(this);

        //mUsageStatsService.monitorPackages();
    }
```
这里调用了两个重要函数:
1. 调用`generateApplicationProvidersLocked`函数,返回了一个`ProviderInfo`集合.
2. 调用`ActivityThread`的`installSystemProviders`,`ActivityThread`可以看作是进程的`Android`运行环境,那么`installSystemProviders`表示为进程安装`ContentProvider`.

- `generateApplicationProvidersLocked`函数

    ```Java
    private final List<ProviderInfo> generateApplicationProvidersLocked(ProcessRecord app) {
        List<ProviderInfo> providers = null;
        try {
            //向PKMS查询满足要求的ProviderInfo，最重要的查询条件包括：进程名和进程uid
            ParceledListSlice<ProviderInfo> slice = AppGlobals.getPackageManager().
                    queryContentProviders(app.processName, app.uid,
                            STOCK_PM_FLAGS | PackageManager.GET_URI_PERMISSION_PATTERNS);
            providers = slice != null ? slice.getList() : null;
        } catch (RemoteException ex) {
        }
        int userId = app.userId;
        if (providers != null) {
            int N = providers.size();
            //保证容器容量大小
            app.pubProviders.ensureCapacity(N + app.pubProviders.size());
            for (int i=0; i<N; i++) {
                ProviderInfo cpi = (ProviderInfo)providers.get(i);
                //是否为单例,如果是单例且用户不相同就要剔除掉
                boolean singleton = isSingleton(cpi.processName, cpi.applicationInfo,
                        cpi.name, cpi.flags);
                if (singleton && UserHandle.getUserId(app.uid) != UserHandle.USER_OWNER) {
                    providers.remove(i);
                    N--;
                    i--;
                    continue;
                }
                ComponentName comp = new ComponentName(cpi.packageName, cpi.name);
                ContentProviderRecord cpr = mProviderMap.getProviderByClass(comp, userId);
                if (cpr == null) {
                    cpr = new ContentProviderRecord(this, cpi, app.info, comp, singleton);
                    //保存到AMS的mProviderMap集合中
                    mProviderMap.putProviderByClass(comp, cpr);
                }
                //将信息也保存到ProcessRecord中
                app.pubProviders.put(cpi.name, cpr);
                if (!cpi.multiprocess || !"android".equals(cpi.packageName)) {
                    //保存PackageName到ProcessRecord中
                    //如果是被多个进程使用的框架层的东西就不用保存了
                    app.addPackage(cpi.applicationInfo.packageName, cpi.applicationInfo.versionCode,
                                mProcessStats);
                }
                //对该APK进行dex优化
                ensurePackageDexOpt(cpi.applicationInfo.packageName);
            }
        }
        return providers;
    }
    ```
    由此可知:`generateApplicationProvidersLocked`先从PKMS那里查询满足条件的`ProviderInfo`信息,而后将它们分别保存到AMS和`ProcessRecord`中对应的数据结构中.
    - 先看查询函数`queryContentProviders`
    ```Java
    public ParceledListSlice<ProviderInfo> queryContentProviders(String processName,
            int uid, int flags) {
        ArrayList<ProviderInfo> finalList = null;
        synchronized (mPackages) {
            //mProviders.mProviders以ComponentName为key，保存了
            //PKMS扫描APK得到的PackageParser.Provider信息
            final Iterator<PackageParser.Provider> i = mProviders.mProviders.values().iterator();
            final int userId = processName != null ?
                    UserHandle.getUserId(uid) : UserHandle.getCallingUserId();
            while (i.hasNext()) {
                final PackageParser.Provider p = i.next();
                PackageSetting ps = mSettings.mPackages.get(p.owner.packageName);
                //下面的if语句将从这些Provider中搜索本例设置的processName为“system”，
                //uid为SYSTEM_UID，flags为FLAG_SYSTEM的Provider
                if (ps != null && p.info.authority != null
                        && (processName == null
                                || (p.info.processName.equals(processName)
                                        && UserHandle.isSameApp(p.info.applicationInfo.uid, uid)))
                        && mSettings.isEnabledLPr(p.info, flags, userId)
                        && (!mSafeMode
                                || (p.info.applicationInfo.flags & ApplicationInfo.FLAG_SYSTEM) != 0)) {
                    //初始化集合
                    if (finalList == null) {
                        finalList = new ArrayList<ProviderInfo>(3);
                    }
                    //通过PackageParser.Provider得到对应的ProviderInfo信息
                    ProviderInfo info = PackageParser.generateProviderInfo(p, flags,
                            ps.readUserState(userId), userId);
                    //添加到集合中
                    if (info != null) {
                        finalList.add(info);
                    }
                }
            }
        }
        if (finalList != null) {
            //最终结果按provider的initOrder排序，该值用于表示初始化ContentProvider的顺序
            Collections.sort(finalList, mProviderInitOrderSorter);
            return new ParceledListSlice<ProviderInfo>(finalList);
        }
        return null;
    }
    ```
    从`SettingsProvider`的`AndroidManifest.xml`中可知:
    ```Xml
    <manifest xmlns:android="http://schemas.android.com/apk/res/android"
        package="com.android.providers.settings"
        coreApp="true"
        android:sharedUserId="android.uid.system">
        <application android:allowClearUserData="false"
                     android:label="@string/app_label"
                     android:process="system"
                     android:backupAgent="SettingsBackupAgent"
                     android:killAfterRestore="false"
                     android:icon="@mipmap/ic_launcher_settings">
            <provider android:name="SettingsProvider"             android:authorities="settings"
                  android:multiprocess="false"
                  android:exported="true"
                  android:singleUser="true"
                  android:initOrder="100" />
        </application>
    </manifest>
    ```
    - `SettingsProvider`设置了其`uid`为`android.uid.system`,同时在`application`中设置了`process`名为`system`.
    - 在`framework-res.apk`中也做了相同的设置
    - `SystemServer`的很多`Service`都依赖`Settings`数据库,把它们放在同一个进程中,可以降低由于进程间通信带来的效率损失.

- `ActivityThread` 的`installSystemProviders`函数
    在AMS和`ProcessRecord`中都保存了`Provider`信息,下面要创建一个`ContentProvider`实例(即`SettingsProvider`对象).该工作由`ActivityThread`的`installSystemProviders`来完成
    
    ```Java
    public final void installSystemProviders(List<ProviderInfo> providers) {
        if (providers != null) {
            installContentProviders(mInitialApplication, providers);
        }
    }
    ```
    - `installContentProviders`这个函数是所有`ContentProvider`产生的必经之路
    
    ```Java
    private void installContentProviders(
            Context context, List<ProviderInfo> providers) {
        final ArrayList<IActivityManager.ContentProviderHolder> results =
            new ArrayList<IActivityManager.ContentProviderHolder>();
        for (ProviderInfo cpi : providers) {
            //调用installProvider函数，得到一个ContentProviderHolder对象
            IActivityManager.ContentProviderHolder cph = installProvider(context, null, cpi,
                    false /*noisy*/, true /*noReleaseNeeded*/, true /*stable*/);
            if (cph != null) {
                cph.noReleaseNeeded = true;
                //将对象保存到results中
                results.add(cph);
            }
        }
        try {
            //调用AMS的publishContentProviders注册这些ContentProvider.
            //第一个参数为ApplicationThread
            ActivityManagerNative.getDefault().publishContentProviders(
                getApplicationThread(), results);
        } catch (RemoteException ex) {
        }
    }
    ```
    - `installProvider`函数
    
    ```Java
    private IActivityManager.ContentProviderHolder installProvider(Context context,
            IActivityManager.ContentProviderHolder holder, ProviderInfo info,
            boolean noisy, boolean noReleaseNeeded, boolean stable) {
        /*context= mInitialApplication
         *holder = null
         *info != null
         *noisy = false
         *noReleaseNeeded = true
         *stable = true;
         */
        ContentProvider localProvider = null;
        IContentProvider provider;
        if (holder == null || holder.provider == null) {
            Context c = null;
            ApplicationInfo ai = info.applicationInfo;
            /*
             *下面这个判断是为该contentprovider找到对应的application
             *ContentProvider和Application有一种对应关系
             *本例中传入的context为framework-res.apk,contentprovider为SettingsProvider
             *且对应的application未创建,所以走最后else分支
             */
            if (context.getPackageName().equals(ai.packageName)) {
                c = context;
            } else if (mInitialApplication != null &&
                mInitialApplication.getPackageName().equals(ai.packageName)) {
                c = mInitialApplication;
            } else {
                try {
                    /*
                     *ai.packageName应该是SettingsProvider.apk的Package
                     *名为"com.android.providers.settings"
                     *创建一个Context，指向该APK
                     */
                    c = context.createPackageContext(ai.packageName,
                            Context.CONTEXT_INCLUDE_CODE);
                } catch (PackageManager.NameNotFoundException e) {
                    // Ignore
                }
            }
            ...
            /*
             *只有对应的Context才能加载对应APK的Java字节码
             *从而可通过反射机制生成ContentProvider实例
             */
            try {
                final java.lang.ClassLoader cl = c.getClassLoader();
                //通过Java反射机制得到真正的ContentProvider
                //此处将得到一个SettingsProvider对象
                localProvider = (ContentProvider)cl.
                    loadClass(info.name).newInstance();
                provider = localProvider.getIContentProvider();
                ...
                 //初始化该ContentProvider,内部会调用其onCreate函数
                localProvider.attachInfo(c, info);
            } catch (java.lang.Exception e) {
                ...
            }
        } else {
            provider = holder.provider;
        }
        IActivityManager.ContentProviderHolder retHolder;
        synchronized (mProviderMap) {
            IBinder jBinder = provider.asBinder();
            if (localProvider != null) {
                ComponentName cname = new ComponentName(info.packageName, info.name);
                ProviderClientRecord pr = mLocalProvidersByName.get(cname);
                if (pr != null) {
                    provider = pr.mProvider;
                } else {
                        holder = new IActivityManager.ContentProviderHolder(info);
                        holder.provider = provider;
                        holder.noReleaseNeeded = true;
                        //ContentProvider必须指明一个和多个authority
                        //这个函数就是用来指定ContentProvider的位置
                        pr = installProviderAuthoritiesLocked(provider, localProvider, holder);
                        mLocalProviders.put(jBinder, pr);
                        mLocalProvidersByName.put(cname, pr);
                }
                retHolder = pr.mHolder;
            } else {
                /*
                 *mProviderRefCountMap,类型为HashMap<IBinder,ProviderRefCount>
                 *主要通过ProviderRefCount对ContentProvider进行引用计数控制
                 *一旦引用计数降为零,表示系统中没有地方使用该ContentProvider,要考虑从系统中注销它
                 */
                ...
            }
        }
        return retHolder;
    }
    ```
    - `ContentProvider`类本身只是一个容器,而跨进程调用的支持是通过内部类`Transport`实现的.
    - `Transport`从`ContentProviderNative`派生,而`ContentProvider`的成员变量`mTransport`指向该`Transport`对象.
    - `ContentProvider`的`getIContentProvider`函数即返回`mTransport`成员变量.
    - `ContentProviderNative`从`Binder`派生,并实现了`IContentProvider`接口,其内部类`ContentProviderProxy`是供客户端使用的.
    - `ProviderClientRecord`是`ActivityThread`提供的用于保存`ContentProvider`信息的一个数据结构
        - `mLocalProvider`用于保存ContentProvider对象
        - `mProvider`用于保存`IContentProvider`对象
        - `mName`用于保存该`ContentProvider`的`authority`集合
    
- ASM的`publishContentProviders`函数
    `publicContentProviders`函数用于向AMS注册`ContentProviders`
    ```Java
    public final void publishContentProviders(IApplicationThread caller,
            List<ContentProviderHolder> providers) {
        ...
        synchronized (this) {
            //找到调用者所在的ProcessRecord对象
            final ProcessRecord r = getRecordForAppLocked(caller);
            ...
            final long origId = Binder.clearCallingIdentity();
            final int N = providers.size();
            for (int i=0; i<N; i++) {
                ContentProviderHolder src = providers.get(i);
                ...
                //先从该ProcessRecord中找对应的ContentProviderRecord
                ContentProviderRecord dst = r.pubProviders.get(src.info.name);
                if (dst != null) {
                    ComponentName comp = new ComponentName(dst.info.packageName, dst.info.name);
                    //以ComponentName为key保存在mProviderMap
                    mProviderMap.putProviderByClass(comp, dst);
                    String names[] = dst.info.authority.split(";");
                    for (int j = 0; j < names.length; j++) {
                    //以authority不同的名字作为key保存到mProviderMap
                        mProviderMap.putProviderByName(names[j], dst);
                    }
                    //mLaunchingProviders用于保存处于启动状态的Provider
                    int NL = mLaunchingProviders.size();
                    int j;
                    for (j=0; j<NL; j++) {
                        if (mLaunchingProviders.get(j) == dst) {
                            mLaunchingProviders.remove(j);
                            j--;
                            NL--;
                        }
                    }
                    synchronized (dst) {
                        dst.provider = src.provider;
                        dst.proc = r;
                        dst.notifyAll();
                    }
                    //每发布一个Provider，需要调整对应进程的oom_adj
                    updateOomAdjLocked(r);
                    //判断是否需要更新provider的使用情况
                    maybeUpdateProviderUsageStatsLocked(r, src.info.packageName,
                            src.info.authority);
                }
            }
            Binder.restoreCallingIdentity(origId);
        }
    }
    ```
    流程总结:
    - 先根据调用者的`pid`找到对应的`ProcessRecord`对象.
    - 该`ProcessRecord`的`pubProviders`中保存了`ContentProviderRecord`信息,该信息由前面介绍的AMS的`generateApplicationProvidersLocked`函数根据`Package`本身的信息生成,此处将判断要发布的ContentProvider是否由该Package声明.
    - 如果判断返回成功,则将该`ContentProvider`以`ComponentName`为`key`存放到`mProviderMap`,后续再逐个通过`ContentProvider`的`authority`存放到`mProviderMap`.系统提供了多种方式来找到对应的`ContentProvider`
    - `mLaunchingProviders`和最后的`notifyAll`函数用于通知那些等待`ContentProvider`所在进程启动的客户端进程

## ASM的`systemReady`函数
`systemReady`函数比较复杂,会分为三部分.
## 第一部分工作:
- 第一部分代码:
    ```Java
    public void systemReady(final Runnable goingCallback) {
        //开机闹钟,ANR设置,最近开启的apk
        ...
        synchronized(this) {
            if (!mDidUpdate) {//判断是否为升级
                if (mWaitingUpdate) {
                    return; //升级未完成，直接返回
                }
                final ArrayList<ComponentName> doneReceivers = new ArrayList<ComponentName>();
                mWaitingUpdate = deliverPreBootCompleted(new Runnable() {
                    public void run() {
                        synchronized (ActivityManagerService.this) {
                            mDidUpdate = true;
                        }
                        showBootMessage(mContext.getText(
                                    R.string.android_upgrading_complete),
                                    false);
                            writeLastDonePreBootReceivers(doneReceivers);
                            systemReady(goingCallback);
                        }
                    }, doneReceivers, UserHandle.USER_OWNER);
                if (mWaitingUpdate) {
                    return;
                }
                mDidUpdate = true;
            }
    
            mAppOpsService.systemReady();
            mSystemReady = true;
        }
    ```
    - `deliverPreBootCompleted`函数
    ```Java
    private boolean deliverPreBootCompleted(final Runnable onFinishCallback,
            ArrayList<ComponentName> doneReceivers, int userId) {
        //准备PRE_BOOT_COMPLETED广播
        Intent intent = new Intent(Intent.ACTION_PRE_BOOT_COMPLETED);
        List<ResolveInfo> ris = null;
        try {
            //向PKMS查询该广播的接收者
            ris = AppGlobals.getPackageManager().queryIntentReceivers(
                    intent, null, 0, userId);
        } catch (RemoteException e) {
        }
        if (ris == null) {
            return false;
        }
        //从返回的结果中删除那些非系统APK的广播接收者
        for (int i=ris.size()-1; i>=0; i--) {
            if ((ris.get(i).activityInfo.applicationInfo.flags
                    &ApplicationInfo.FLAG_SYSTEM) == 0) {
                ris.remove(i);
            }
        }
        intent.addFlags(Intent.FLAG_RECEIVER_BOOT_UPGRADE);
        if (userId == UserHandle.USER_OWNER) {
            //读取/data/system/called_pre_boots.dat文件,这里存储了上次启动时候已经
            //并处理PRE_BOOT_COMPLETED广播的组件。鉴于该广播的特殊性，系统希望
            //该广播仅被这些接收者处理一次
            ArrayList<ComponentName> lastDoneReceivers = readLastDonePreBootReceivers();
            //从PKMS返回的接收者中删除那些已经处理过该广播的对象
            for (int i=0; i<ris.size(); i++) {
                ActivityInfo ai = ris.get(i).activityInfo;
                ComponentName comp = new ComponentName(ai.packageName, ai.name);
                if (lastDoneReceivers.contains(comp)) {
                    ris.remove(i);
                    i--;
                    doneReceivers.add(comp);
                }
            }
        }
        if (ris.size() <= 0) {
            return false;
        }
        final int[] users = userId == UserHandle.USER_OWNER ? getUsersLocked()
                : new int[] { userId };
        if (users.length <= 0) {
            return false;
        }
        //保存那些处理过该广播的接收者信息
        //发送广播给指定的接收者
        //最后回调onFinishCallback
        PreBootContinuation cont = new PreBootContinuation(intent, onFinishCallback, doneReceivers,
                ris, users);
        cont.go();
        return true;
    }
    ```
    第一阶段完结,其主要职责是发送并处理与`PRE_BOOT_COMPLETED`广播相关的事情.
## 第二部分工作:
- 第二部分代码

    ```Java
    ArrayList<ProcessRecord> procsToKill = null;
        synchronized(mPidsSelfLocked) {
            for (int i=mPidsSelfLocked.size()-1; i>=0; i--) {
                ProcessRecord proc = mPidsSelfLocked.valueAt(i);
                //从mPidsSelfLocked中找到那些先于AMS启动的进程
                //那些声明了persistent为true的进程有可能
                if (!isAllowedWhileBooting(proc.info)){
                    if (procsToKill == null) {
                        procsToKill = new ArrayList<ProcessRecord>();
                    }
                    procsToKill.add(proc);
                }
            }
        }
        synchronized(this) {
            if (procsToKill != null) {
                for (int i=procsToKill.size()-1; i>=0; i--) {
                    ProcessRecord proc = procsToKill.get(i);
                    Slog.i(TAG, "Removing system update proc: " + proc);
                    //把这些进程关闭
                    removeProcessLocked(proc, true, false, "system update done");
                }
            }
            //系统准备完毕
            mProcessesReady = true;
        }
        ...//工厂测试相关
        retrieveSettings();//查询Settings数据,获得配置信息
        loadResourcesOnSystemReady();//加载资源,必须在config获取后
    ```
总结:
- 杀死那些竟然在AMS还未启动完毕就先启动的应用进程.(只有应用程序才会经过AMS,`Native`进程不经过AMS)
- 从`Settings`数据库中获取配置信息,主要获取如下信息
    - debug_app (设置需要debug的app的名称)
    - waitForDebugger (如果为1，则等待调试器，否则正常启动debug_app)
    - alwaysFinishActivities (当一个activity不再有地方使用时，是否立即对它执行destroy)
    - forceRtl (从右向左语言判断)
    - configuration(包括字体大小,语言,地区等)
- 加载资源
    - mHasRecents (是否存在最近活动的UI)
    - mThumbnailWidth (最近活动UI的宽度)
    - mThumbnailHeight (最近活动UI的高度)

## 第三部分工作
- 第三部分代码
    ```Java
    //systemReady参数,一个线程
    if (goingCallback != null) goingCallback.run();
    //多用户的电池损耗情况
    mBatteryStatsService.noteEvent(BatteryStats.HistoryItem.EVENT_USER_RUNNING_START,
        Integer.toString(mCurrentUserId), mCurrentUserId);
    mBatteryStatsService.noteEvent(BatteryStats.HistoryItem.EVENT_USER_FOREGROUND_START,
        Integer.toString(mCurrentUserId), mCurrentUserId);
    mSystemServiceManager.startUser(mCurrentUserId);
    synchronized (this) {
        if (mFactoryTest != FactoryTest.FACTORY_TEST_LOW_LEVEL) {
            try {
                //从PKMS中查询那些persistent为1的ApplicationInfo
                List apps = AppGlobals.getPackageManager().
                    getPersistentApplications(STOCK_PM_FLAGS);
                if (apps != null) {
                    int N = apps.size();
                    int i;
                    for (i=0; i<N; i++) {
                        ApplicationInfo info                                = (ApplicationInfo)apps.get(i);
                        //由于framework-res.apk已由系统启动,所以这里需要去除掉它
                        //framework-res.apk的包名为"android"
                        if (info != null &&
                                !info.packageName.equals("android")) {
                            //启动该Application所在的进程
                            addAppLocked(info, false, null /* ABI override */);
                        }
                    }
                }
            } catch (RemoteException ex) {
                // pm is in same process, this will never happen.
            }
        }
        mBooting = true;//设置mBooting变量为true
        try {
            if (AppGlobals.getPackageManager().hasSystemUidErrors()) {
                Slog.e(TAG, "UIDs on the system are inconsistent, you need to wipe your"
                        + " data partition or your device will be unstable.");
                //处理那些Uid有错误的Application
                mUiHandler.obtainMessage(SHOW_UID_ERROR_MSG).sendToTarget();
            }
        } catch (RemoteException e) {
        }
        //发送了两个系统广播
        //ACTION_USER_STARTED 用户启动
        //ACTION_USER_STARTING  用户正在启动
        ...
        //启动全系统第一个Activity，即Home
        mStackSupervisor.resumeTopActivitiesLocked();
    ```
    `systemReady`第三阶段的工作：
    - 调用`systemReady`设置的回调对象`goingCallback`的run函数
    - 启动那些声明了`persistent`的APK
    - 发送了用户广播
    - 启动桌面
  
- `goingCallback`的run函数

    `SystemServer`中`startOtherServices`函数会调用AMS的`SystemReady`函数並传入`goingCallBack`的回调.代码如下:
    ```Java
    mActivityManagerService.systemReady(new Runnable() {
            @Override
            public void run() {
                ...
                //Boot状态更换,AMA准备好了
                mSystemServiceManager.startBootPhase(
                        SystemService.PHASE_ACTIVITY_MANAGER_READY);
                try {
                    //启动SystemUi
                    startSystemUi(context);
                } catch (Throwable e) {
                    reportWtf("starting System UI", e);
                }
                ...//调用其他服务的systemReady函数
                Watchdog.getInstance().start();//启动Watchdog
                //Boot状态更换,第三方应用可以开启
                mSystemServiceManager.startBootPhase(
                        SystemService.PHASE_THIRD_PARTY_APPS_CAN_START);
                ...//调用其他服务的systemRunning函数
        }
    }
    ```
    `run`函数做了如下工作:
    - 将`BootPhase`更新到`PHASE_THIRD_PARTY_APPS_CAN_START`状态
    - 执行了`startSystemUi`,内部启动了`SystemUIService`
    - 开启了`watchdog`
    - 调用了一些服务的`systemReady`和`systemRunning`
    开启`SystemUi`代码:
    ```Java
    static final void startSystemUi(Context context) {
        Intent intent = new Intent();
        intent.setComponent(new ComponentName("com.android.systemui",
                    "com.android.systemui.SystemUIService"));
        context.startServiceAsUser(intent, UserHandle.OWNER);
    }
    ```
    `SystemUIService`由`SystemUi.apk`提供，它实现了系统的状态栏
    
- 启动`home`界面

    `ActivityStackSupervisor`的`resumeTopActivitiesLocked`函数

    ```Java
    boolean resumeTopActivitiesLocked() {
        return resumeTopActivitiesLocked(null, null, null);
    }
    ```
    调用了有参数的`resumeTopActivitiesLocked`且参数为空
    ```Java
    boolean resumeTopActivitiesLocked(ActivityStack targetStack, ActivityRecord target,
            Bundle targetOptions) {
        if (targetStack == null) {
            targetStack = mFocusedStack;
        }
        ...
        //判断了targetStack == mFocusedStack
        if (isFrontStack(targetStack)) {
            result = targetStack.resumeTopActivityLocked(target, targetOptions);
        }
        ...
        return result;
    }
    ```
    调用了`ActivityStack`的`resumeTopActivityLocked`函数
    ```Java
    try {
        //更改标志
        // Protect against recursion.
        mStackSupervisor.inResumeTopActivity = true;
        //判断是否需要锁屏
        if (mService.mLockScreenShown == ActivityManagerService.LOCK_SCREEN_LEAVING) {
            mService.mLockScreenShown = ActivityManagerService.LOCK_SCREEN_HIDDEN;
            mService.updateSleepIfNeededLocked();
        }
        result = resumeTopActivityInnerLocked(prev, options);
    } finally {
        mStackSupervisor.inResumeTopActivity = false;
    }
    ```
    调用`resumeTopActivityInnerLocked`函数
    ```Java
    ...
    // Find the first activity that is not finishing.
    final ActivityRecord next = topRunningActivityLocked(null);
    final boolean userLeaving = mStackSupervisor.mUserLeaving;
    mStackSupervisor.mUserLeaving = false;
    final TaskRecord prevTask = prev != null ? prev.task : null;
    if (next == null) {
        final String reason = "noMoreActivities";
        final int returnTaskType = prevTask == null || !prevTask.isOverHomeStack() ?
                    HOME_ACTIVITY_TYPE : prevTask.getTaskToReturnTo();
        ...
        return isOnHomeDisplay() &&
                    mStackSupervisor.resumeHomeStackTask(returnTaskType, prev, reason);
    }
    ...
    ```
    由于参数`prev`和`options`为空, 所以调用`StackSupervisor`的`resumeHomeStackTask`函数
    参数列表
    - `returnTaskType` = `HOME_ACTIVITY_TYPE`
    - `prev` = `null`
    - `reason` = `noMoreActivities`
    ```Java
    boolean resumeHomeStackTask(int homeStackTaskType, ActivityRecord prev, String reason) {
        ...
        mHomeStack.moveHomeStackTaskToTop(homeStackTaskType);
        //homeActivity还没打开,所以r = null
        ActivityRecord r;
        if (mService.mBooting) {
            r = getRunningHomeActivityForUser(mCurrentUser);
        } else {
            r = getHomeActivity();
        }
        if (r != null) {
            mService.setFocusedActivityLocked(r, reason);
            return resumeTopActivitiesLocked(mHomeStack, prev, null);
        }
        //由于为空 调用startHomeActivityLocked
        //mService指向AMS
        return mService.startHomeActivityLocked(mCurrentUser, reason);
    }
    ```
    调用了AMS的`startHomeActivityLocked`函数,和开机闹钟殊途同归了
    AMS的`startHomeActivityLocked`函数
    ```Java
    boolean startHomeActivityLocked(int userId, String reason) {
        //获得桌面的intent
        Intent intent = getHomeIntent();
        //向PKMS查询满足条件的ActivityInfo
        ActivityInfo aInfo =
            resolveActivityInfo(intent, STOCK_PM_FLAGS, userId);
        if (aInfo != null) {
            intent.setComponent(new ComponentName(
                    aInfo.applicationInfo.packageName, aInfo.name));
            aInfo = new ActivityInfo(aInfo);
            aInfo.applicationInfo = getAppInfoForUser(aInfo.applicationInfo, userId);
            ProcessRecord app = getProcessRecordLocked(aInfo.processName,
                    aInfo.applicationInfo.uid, true);
             //在正常情况下，app应该为null，因为刚开机，Home进程肯定还没启动
            if (app == null || app.instrumentationClass == null) {
                intent.setFlags(intent.getFlags() | Intent.FLAG_ACTIVITY_NEW_TASK);
                //启动Home
                mStackSupervisor.startHomeActivity(intent, aInfo, reason);
            }
        }
        return true;
    }
    ```
    `StackSupervisor`的`startHomeActivity`函数
    ```Java
    void startHomeActivity(Intent intent, ActivityInfo aInfo, String reason) {
        //将home移到顶部
        moveHomeStackTaskToTop(HOME_ACTIVITY_TYPE, reason);
        //开启home
        startActivityLocked(null /* caller */, intent, null /* resolvedType */, aInfo,
                null /* voiceSession */, null /* voiceInteractor */, null /* resultTo */,
                null /* resultWho */, 0 /* requestCode */, 0 /* callingPid */, 0 /* callingUid */,
                null /* callingPackage */, 0 /* realCallingPid */, 0 /* realCallingUid */,
                0 /* startFlags */, null /* options */, false /* ignoreTargetSecurity */,
                false /* componentSpecified */,
                null /* outActivity */, null /* container */,  null /* inTask */);
        if (inResumeTopActivity) {
            // If we are in resume section already, home activity will be initialized, but not
            // resumed (to avoid recursive resume) and will stay that way until something pokes it
            // again. We need to schedule another resume.
            scheduleResumeTopActivities();
        }
    }
    ```
    至此，AMS携各个`Service`都启动完毕，`Home`也启动了,整个系统就准备完毕.
3. 发送`ACTION_BOOT_COMPLETED`广播
        
        系统准备好了,就要发送开机广播了.
        开机广播应用非常广泛,让我们看看在哪发送的.
        当`Home Activity`启动后，`ActivityStackSupervisor`的`activityIdleInternalLocked`函数将被调用
        ```Java
        final ActivityRecord activityIdleInternalLocked(final IBinder token, boolean fromTimeout,
            Configuration config) {
            ...
            ActivityRecord r = ActivityRecord.forTokenLocked(token);
        if (r != null) {
            ...
            if (isFrontStack(r.task.stack) || fromTimeout) {
                booting = checkFinishBootingLocked();
            }
        }
        ```
        `checkFinishBootingLocked`函数是用来确定是否开机完成
        ```Java
        private boolean checkFinishBootingLocked() {
            //在systemReady中设置为true
            final boolean booting = mService.mBooting;
            boolean enableScreen = false;
            mService.mBooting = false;
            if (!mService.mBooted) {
                mService.mBooted = true;
                enableScreen = true;
            }
            if (booting || enableScreen) {
            //booting = true enableScreen = true
                mService.postFinishBooting(booting, enableScreen);
            }
            return booting;
        }
        ```
        发消息`postFinishBooting`.
        ```Java
        void postFinishBooting(boolean finishBooting, boolean enableScreen) {
            //两个值均为1
            mHandler.sendMessage(mHandler.obtainMessage(FINISH_BOOTING_MSG,
                finishBooting ? 1 : 0, enableScreen ? 1 : 0));
        }
        ```
        看如何处理消息的
        ```Java
        case FINISH_BOOTING_MSG: {
            if (msg.arg1 != 0) {
                finishBooting();
            }
            if (msg.arg2 != 0) {
                enableScreenAfterBoot();
            }
                break;
        }
        ```
        `finishBooting`就是来发送开机完成广播的
        ```Java
        final void finishBooting() {
            //确保已经播完开机动画了
            //确保已经开机完成了
            ...
            //防止在闹钟沉睡后再做odex
            markBootComplete();
            //处理Package重启的广播
            IntentFilter pkgFilter = new IntentFilter();
            pkgFilter.addAction(Intent.ACTION_QUERY_PACKAGE_RESTART);
            pkgFilter.addDataScheme("package");
            mContext.registerReceiver(new BroadcastReceiver() {
                ...
            }
            //决定什么时候删除无用内存
            IntentFilter dumpheapFilter = new IntentFilter();
            dumpheapFilter.addAction(DumpHeapActivity.ACTION_DELETE_DUMPHEAP);
            mContext.registerReceiver(new BroadcastReceiver() {
            ...
            }
            //让system service知道
            mSystemServiceManager.startBootPhase(SystemService.PHASE_BOOT_COMPLETED);
            //避免执行addBootEvent来提高性能
            mBootProfIsEnding = true;
            synchronized (this) {
                final int NP = mProcessesOnHold.size();
            if (NP > 0) {
                ArrayList<ProcessRecord> procs =
                    new ArrayList<ProcessRecord>(mProcessesOnHold);
                for (int ip=0; ip<NP; ip++) {
                    //启动那些等待启动的进程 
                    startProcessLocked(procs.get(ip), "on-hold", null);
                }
            }
            if (mFactoryTest != FactoryTest.FACTORY_TEST_LOW_LEVEL) {
                //每15钟检查系统各应用进程使用电量的情况,如果某进程使用WakeLock时间
                //过长,AMS将关闭该进程
                Message nmsg = mHandler.obtainMessage(CHECK_EXCESSIVE_WAKE_LOCKS_MSG);
                mHandler.sendMessageDelayed(nmsg, POWER_CHECK_DELAY);
                //设置系统属性sys.boot_completed的值为1
                SystemProperties.set("sys.boot_completed", "1");
                //多用户发送开机完成广播
                for (int i=0; i<mStartedUsers.size(); i++) {
                    UserState uss = mStartedUsers.valueAt(i);
                    if (uss.mState == UserState.STATE_BOOTING) {
                        uss.mState = UserState.STATE_RUNNING;
                        final int userId = mStartedUsers.keyAt(i);
                        Intent intent = new Intent(Intent.ACTION_BOOT_COMPLETED, null);
                        intent.putExtra(Intent.EXTRA_USER_HANDLE, userId);
                        intent.addFlags(Intent.FLAG_RECEIVER_NO_ABORT);
                        broadcastIntentLocked(null, null, intent, null,
                            new IIntentReceiver.Stub() {
                                    @Override
                                    public void performReceive(Intent intent, int resultCode,
                                            String data, Bundle extras, boolean ordered,
                                            boolean sticky, int sendingUser) {
                                        synchronized (ActivityManagerService.this) {
                                            requestPssAllProcsLocked(SystemClock.uptimeMillis(),
                                                    true, false);)
                                            mAmPlus.monitorBootReceiver(false, "Normal Bootup End");
                                        }
                                    }
                                },
                                0, null, null,
                                new String[] {android.Manifest.permission.RECEIVE_BOOT_COMPLETED},
                                AppOpsManager.OP_NONE, null, true, false,
                                MY_PID, Process.SYSTEM_UID, userId);
                        }
                    }
                    scheduleStartProfilesLocked();
                }
                //确保只开机一次
                mDoneFinishBooting = true;
            }
            //做一些记录工作
            ...
        }
        ```
    4. `systemReady`总结
        `systemReady`函数完成了系统就绪的必要工作,然后它将启动`Home Activity`.至此,`Android系统`就全部启动了.
    
## `ActivityManagerService`初始化总结
- AMS的`构造函数`:获得`ActivityThread`对象,通过该对象创建`Android运行环境`,得到一个`ActivityThread`和一个`Context对象`.
- AMS的`setSystemProcess`函数:注册AMS和`meminfo`等服务到`ServiceManager`中.另外,它为`SystemServer`创建了一个`ProcessRecord`对象,便于管理`SystemServer`系统进程
- AMS的`installSystemProviders`函数:为`SystemServer`加载`SettingsProvider`
- AMS的`systemReady`函数:做系统启动完毕前最后一些扫尾工作

## `startActivity`流程
在这里,主要讲述的是从`am`来启动`Activity`的过程,从`am`来分析`Activity`的启动也是`Activity`启动分析中相对简单的一条路线

1. `AM`的工作:
    通过`AM`启动`Activity`中依次调用了`run(args)`,`onRun()`,`runStart()`,根最后同`AMS`交互,根据是否有参数`-W`来判断是调用`AMS`的`startActivityAndWait`还是调用`AMS`的`startActivityAsUser`来处理`Activity`启动请求

2. `AMS`处理请求
    无论是否有`-W`参数,都会调用`ActivityStackSupervisor`的`startActivityMayWait`函数

3. `ActivityStackSupervisor`的`startActivityMayWait`
    
    ```Java
    final int startActivityMayWait(
            /*
             *在绝大多数情况下,一个Acitivity的启动是由一个应用进程发起的
             *IApplicationThread是应用进程和AMS交互的通道,也可算是调用进程的标示
             *在本例中,AM并非一个应用进程,所以传递的caller为null
             */
            IApplicationThread caller,
            /*调用进程的uid*/
            int callingUid,
            /*调用包名*/
            String callingPackage, 
            /*intent和resolvedType,这里resolvedType = null*/
            Intent intent, 
            String resolvedType,
            /*这里为null*/
            IVoiceInteractionSession voiceSession, 
            IVoiceInteractor voiceInteractor,
            /*在这里为null,用于接收startActivityForResult的结果*/
            IBinder resultTo,
            /*在本例中为null*/
            String resultWho,
            /*在本例中为0,该值的具体意义由调用者解释.如果该值大于等于0，则AMS内部保存该值
             *并通过onActivityResult返回给调用者
             */
            int requestCode,
            /*1<<1 debug
             *1<<2 openGL 跟踪
             */
            int startFlags,
            /*参数为空*/
            ProfilerInfo profilerInfo,
            /*保存的信息*/
            WaitResult outResult, 
            /*配置信息,这里为null*/
            Configuration config,
            /*这里为null*/
            Bundle options, 
            /*这里为false*/
            boolean ignoreTargetSecurity,
            /*用户*/
            int userId,
            /*这里为null*/
            IActivityContainer iContainer,
            /*这里为null*/
            TaskRecord inTask
            ) {
        ...
        //getComponent不为空 所以为true
        boolean componentSpecified = intent.getComponent() != null;
        //不要修改原来的对象
        intent = new Intent(intent);
        //查询满足条件的ActivityInfo,在resolveActivity内部和PKMS交互
        ActivityInfo aInfo =
                resolveActivity(intent, resolvedType, startFlags, profilerInfo, userId);
        ActivityContainer container = (ActivityContainer)iContainer;
        synchronized (mService) {
            final int realCallingPid = Binder.getCallingPid();//取出调用进程的Pid
            final int realCallingUid = Binder.getCallingUid();//取出调用进程的Uid
            int callingPid;
            if (callingUid >= 0) {
                callingPid = -1;
            } else if (caller == null) {//在这里 caller为null
                callingPid = realCallingPid;
                callingUid = realCallingUid;
            } else {
                callingPid = callingUid = -1;
            }
            //判断需要将activity保存到哪个stack中.
            //mFocusedStack保存除桌面以外的应用的activity
            final ActivityStack stack;
            if (container == null || container.mStack.isOnHomeDisplay()) {
                stack = mFocusedStack;
            } else {
                stack = container.mStack;
            }
            //mConfigWillChange为false,不用调用updateConfiguration
            stack.mConfigWillChange = config != null && mService.mConfiguration.diff(config) != 0;
            /*解析HeavyWeightProcess*/
            ...
             //调用此函数启动Activity,将返回值保存到res
            int res = startActivityLocked(caller, intent, resolvedType, aInfo,
                    voiceSession, voiceInteractor, resultTo, resultWho,
                    requestCode, callingPid, callingUid, callingPackage,
                    realCallingPid, realCallingUid, startFlags, options, ignoreTargetSecurity,
                    componentSpecified, null, container, inTask);
            //如果configuration发生变化,则调用AMS的updateConfigurationLocked
            if (stack.mConfigWillChange) {
                mService.enforceCallingPermission(android.Manifest.permission.CHANGE_CONFIGURATION,
                        "updateConfiguration()");
                stack.mConfigWillChange = false;
                mService.updateConfigurationLocked(config, null, false, false);
            }
            if (outResult != null) {//-W才会进入此分支
                outResult.result = res;//设置启动结果
                if (res == ActivityManager.START_SUCCESS) {
                    //将该结果加到mWaitingActivityLaunched中保存
                    mWaitingActivityLaunched.add(outResult);
                    do {
                        try {
                            mService.wait();//等待启动结果
                        } catch (InterruptedException e) {
                        }
                    } while (!outResult.timeout && outResult.who == null);
                } else if (res == ActivityManager.START_TASK_TO_FRONT) {
                    //找到下一个要启动的Activity
                    ActivityRecord r = stack.topRunningActivityLocked(null);
                    //判断状态是否可见和是否在resume状态,是就直接显示
                    if (r.nowVisible && r.state == RESUMED) {
                        outResult.timeout = false;
                        outResult.who = new ComponentName(r.info.packageName, r.info.name);
                        outResult.totalTime = 0;
                        outResult.thisTime = 0;
                    } else {
                        //加入到mWaitingActivityVisible中
                        outResult.thisTime = SystemClock.uptimeMillis();
                        mWaitingActivityVisible.add(outResult);
                        do {
                            try {
                                mService.wait();//等待启动结果
                            } catch (InterruptedException e) {
                            }
                        } while (!outResult.timeout && outResult.who == null);
                    }
                }
            }

            return res;
        }
    }
    ```
    `startActivityMayWait`主要工作为:
    
    - 需要通过`PKMS`查找匹配该`Intent`的`ActivityInfo`
    - 处理`FLAG_CANT_SAVE_STATE`的情况
    - 获取调用者的pid和uid
    - 启动`Activity`的核心函数`startActivityLocked`
    - 根据返回值做一些处理.目标`Activity`要运行在一个新的应用进程中,就必须等待那个应用进程正常启动并处理相关请求(只有am设置了-W选项,才会进入wait这一状态)
4. `ActivityStackSupervisor`核心函数`startActivityLocked`
    ```Java
    final int startActivityLocked(IApplicationThread caller,
            Intent intent, String resolvedType, ActivityInfo aInfo,
            IVoiceInteractionSession voiceSession, IVoiceInteractor voiceInteractor,
            IBinder resultTo, String resultWho, int requestCode,
            int callingPid, int callingUid, String callingPackage,
            int realCallingPid, int realCallingUid, int startFlags, Bundle options,
            boolean ignoreTargetSecurity, boolean componentSpecified, ActivityRecord[] outActivity,
            ActivityContainer container, TaskRecord inTask) {
        int err = ActivityManager.START_SUCCESS;
        
        ProcessRecord callerApp = null;
        //如果caller不为空,需要通过AMS来获取它的ProcessRecord,这里为空
        if (caller != null) {
            callerApp = mService.getRecordForAppLocked(caller);
            //其实是为了获得pid和uid
            if (callerApp != null) {
                //一定要保证调用进程的pid和uid正确
                callingPid = callerApp.pid;
                callingUid = callerApp.info.uid;
            } else {//如调用进程没有在AMS中注册,则认为其是非法的
                err = ActivityManager.START_PERMISSION_DENIED;
            }
        }
        //判断userId的值
        final int userId = aInfo != null ? UserHandle.getUserId(aInfo.applicationInfo.uid) : 0;
        /*
         * sourceRecord用于描述启动目标Activity的那个Activity
         * resultRecord用于描述接收启动结果的Activity,即该Activity的onActivityResult将被调用以通知启动结果
         */
        ActivityRecord sourceRecord = null;
        ActivityRecord resultRecord = null;
        if (resultTo != null) {//这里为null
            sourceRecord = isInAnyStackLocked(resultTo);
            if (sourceRecord != null) {
                if (requestCode >= 0 && !sourceRecord.finishing) {
                    resultRecord = sourceRecord;
                }
            }
        }
        //获取Intent设置的启动标志
        final int launchFlags = intent.getFlags();
        ...//处理flag.
         //检查err值及Intent的情况
        if (err == ActivityManager.START_SUCCESS && intent.getComponent() == null) {
            err = ActivityManager.START_INTENT_NOT_RESOLVED;
        }
        //判断err值和一些错误情况
        ...
        //获取resultRecord的Stack信息
        final ActivityStack resultStack = resultRecord == null ? null : resultRecord.task.stack;
        //如果err不为0,且resultRecord不为空,则调用sendActivityResultLocked返回错误
        if (err != ActivityManager.START_SUCCESS) {
            if (resultRecord != null) {
                resultStack.sendActivityResultLocked(-1,
                    resultRecord, resultWho, requestCode,
                    Activity.RESULT_CANCELED, null);
            }
            ActivityOptions.abort(options);
            return err;
        }
        //是否需要中止的flag
        boolean abort = false;
        //检查权限
        final int startAnyPerm = mService.checkPermission(
                START_ANY_ACTIVITY, callingPid, callingUid);
        ...//权限检查失败的处理.
        //检查是否启动的inte
        abort |= !mService.mIntentFirewall.checkStartActivity(intent, callingUid,
                callingPid, resolvedType, aInfo.applicationInfo);
        //可为AMS设置一个IActivityController类型的监听者,AMS有任何动静都会回调该监听者
        //主要用于Monkey测试
        if (mService.mController != null) {
            try {
                Intent watchIntent = intent.cloneFilter();
                //交给回调对象处理，由它判断是否能继续后面的行程
                abort |= !mService.mController.activityStarting(watchIntent,
                        aInfo.applicationInfo.packageName);
            } catch (RemoteException e) {
                mService.mController = null;
            }
        }
        //判断是否需要中止,不管是权限问题还是测试时黑名单不允许,全部返回canceled信息
        if (abort) {
            if (resultRecord != null) {
                resultStack.sendActivityResultLocked(-1, resultRecord, resultWho, requestCode,
                        Activity.RESULT_CANCELED, null);
            }
            ActivityOptions.abort(options);
            return ActivityManager.START_SUCCESS;
        }
        //创建一个ActivityRecord对象
        ActivityRecord r = new ActivityRecord(mService, callerApp, callingUid, callingPackage,
                intent, resolvedType, aInfo, mService.mConfiguration, resultRecord, resultWho,
                requestCode, componentSpecified, voiceSession != null, this, container, options);
        if(outActivity != null) {
            outActivity[0] = r;//保存到输入参数outActivity数组中
        }
        final ActivityStack stack = mFocusedStack;
        //mResumedActivity代表当前界面显示的Activity
        if (voiceSession == null && (stack.mResumedActivity == null
                || stack.mResumedActivity.info.applicationInfo.uid != callingUid)) {
            //检查调用进程是否有权限切换Application
            if (!mService.checkAppSwitchAllowedLocked(callingPid, callingUid,
                    realCallingPid, realCallingUid, "Activity start")) {
                //如果调用进程没有权限切换Activity,则只能把这次Activity启动请求保存起来
                //后续有机会时再启动它
                PendingActivityLaunch pal =
                        new PendingActivityLaunch(r, sourceRecord, startFlags, stack);
                //所有Pending的请求均保存到AMS mPendingActivityLaunches变量中
                mPendingActivityLaunches.add(pal);
                ActivityOptions.abort(options);
                return ActivityManager.START_SWITCHES_CANCELED;
            }
        }
        //用于控制app switch
        if (mService.mDidAppSwitch) {
            mService.mAppSwitchesAllowedTime = 0;
        } else {
            mService.mDidAppSwitch = true;
        }
        //启动处于Pending状态的Activity
        doPendingActivityLaunchesLocked(false);
         //调用startActivityUncheckedLocked函数
        err = startActivityUncheckedLocked(r, sourceRecord, voiceSession, voiceInteractor,
                startFlags, true, options, inTask);
        //同WMS交互,去掉keyguard
        if (err < 0) {
            notifyActivityDrawnForKeyguard();
        }
        return err;
    }
    ```
    `startActivityLocked`主要工作:
    - 处理`sourceRecord`及`resultRecord`.其中,`sourceRecord`表示发起本次请求的`Activity`,`resultRecord`表示接收处理结果的`Activity`(启动一个`Activity`肯定需要它完成某项事情,当目标`Activity`将事情成后,就需要告知请求者该事情的处理结果).在一般情况下,`sourceRecord`和`resultRecord`应指向同一个`Activity`.
    - 处理`app Switch`.如果AMS当前禁止`app switch`,则只能把本次启动请求保存起来.以待允许`app switch`时再处理
    - 调用`startActivityUncheckedLocked`处理本次`Activity`启动请求

5. `ActivityStackSupervisor`的`startActivityUncheckedLocked`函数
    - 第一部分代码
    
    ```Java
    final int startActivityUncheckedLocked(final ActivityRecord r, ActivityRecord sourceRecord,
            IVoiceInteractionSession voiceSession, IVoiceInteractor voiceInteractor, int startFlags,
            boolean doResume, Bundle options, TaskRecord inTask) {
        /* 在此例中
         * sourceRecord = null
         * doResume = true
         * inTask = null
         */
        final Intent intent = r.intent;
        final int callingUid = r.launchedFromUid;
        //获取启动模式
        final boolean launchSingleTop = r.launchMode == ActivityInfo.LAUNCH_SINGLE_TOP;
        final boolean launchSingleInstance = r.launchMode == ActivityInfo.LAUNCH_SINGLE_INSTANCE;
        final boolean launchSingleTask = r.launchMode == ActivityInfo.LAUNCH_SINGLE_TASK;
        int launchFlags = intent.getFlags();
        if ((launchFlags & Intent.FLAG_ACTIVITY_NEW_DOCUMENT) != 0 &&
                (launchSingleInstance || launchSingleTask)) {
            //属性和manifest冲突 以manifest为准
            launchFlags &=
                    ~(Intent.FLAG_ACTIVITY_NEW_DOCUMENT | Intent.FLAG_ACTIVITY_MULTIPLE_TASK);
        } else {
            //为了防止onActivityResult在singleTask或singleInstance出错
            switch (r.info.documentLaunchMode) {
                case ActivityInfo.DOCUMENT_LAUNCH_NONE:
                    break;
                case ActivityInfo.DOCUMENT_LAUNCH_INTO_EXISTING:
                    launchFlags |= Intent.FLAG_ACTIVITY_NEW_DOCUMENT;
                    break;
                case ActivityInfo.DOCUMENT_LAUNCH_ALWAYS:
                    launchFlags |= Intent.FLAG_ACTIVITY_NEW_DOCUMENT;
                    break;
                case ActivityInfo.DOCUMENT_LAUNCH_NEVER:
                    launchFlags &= ~Intent.FLAG_ACTIVITY_MULTIPLE_TASK;
                    break;
            }
        }
        final boolean launchTaskBehind = r.mLaunchTaskBehind
                && !launchSingleTask && !launchSingleInstance
                && (launchFlags & Intent.FLAG_ACTIVITY_NEW_DOCUMENT) != 0;
        if ((launchFlags & Intent.FLAG_ACTIVITY_NEW_DOCUMENT) != 0 && r.resultTo == null) {
            launchFlags |= Intent.FLAG_ACTIVITY_NEW_TASK;
        }
        //添加需要的flag
        if ((launchFlags & Intent.FLAG_ACTIVITY_NEW_TASK) != 0) {
            if (launchTaskBehind
                    || r.info.documentLaunchMode == ActivityInfo.DOCUMENT_LAUNCH_ALWAYS) {
                launchFlags |= Intent.FLAG_ACTIVITY_MULTIPLE_TASK;
            }
        }
        //判断是否需要调用因本次Activity启动而被系统移到后台的当前Activity的onUserLeaveHint函数
        //由用户自己将activity调到后台就会回调onUserLeaveHint
        mUserLeaving = (launchFlags & Intent.FLAG_ACTIVITY_NO_USER_ACTION) == 0;
        //这里doResume为true
        if (!doResume) {
            r.delayedResume = true;
        }
        //这里Intent.FLAG_ACTIVITY_PREVIOUS_IS_TOP没有置位 notTop为空
        ActivityRecord notTop =
                (launchFlags & Intent.FLAG_ACTIVITY_PREVIOUS_IS_TOP) != 0 ? r : null;
        //这里没有START_FLAG_ONLY_IF_NEEDED
        if ((startFlags&ActivityManager.START_FLAG_ONLY_IF_NEEDED) != 0) {
            ...
        }
    boolean addingToTask = false;
    TaskRecord reuseTask = null;
    if (sourceRecord == null && inTask != null && inTask.stack != null) {
        final Intent baseIntent = inTask.getBaseIntent();
        final ActivityRecord root = inTask.getRootActivity();
        ...//判断不满足条件的情况
        //如果task为空,就选择合适的intent来启动activity
        if (root == null) {
            final int flagsOfInterest = Intent.FLAG_ACTIVITY_NEW_TASK
                    | Intent.FLAG_ACTIVITY_MULTIPLE_TASK | Intent.FLAG_ACTIVITY_NEW_DOCUMENT
                   | Intent.FLAG_ACTIVITY_RETAIN_IN_RECENTS;
            launchFlags = (launchFlags&~flagsOfInterest)
                    | (baseIntent.getFlags()&flagsOfInterest);
            intent.setFlags(launchFlags);
            inTask.setIntent(r);
            addingToTask = true;
        } else if ((launchFlags & Intent.FLAG_ACTIVITY_NEW_TASK) != 0) {
            //如果task不为空,且需要新开一个task,我们不添加到该task中
            addingToTask = false;
        } else {
            addingToTask = true;
        }
        reuseTask = inTask;
    } else {
        inTask = null;
    }
    if (inTask == null) {
         //如果源record者为空,则当然需要新建一个Task
        if (sourceRecord == null) {
            if ((launchFlags & Intent.FLAG_ACTIVITY_NEW_TASK) == 0 && inTask == null) {
                launchFlags |= Intent.FLAG_ACTIVITY_NEW_TASK;
            }
        } else if (sourceRecord.launchMode == ActivityInfo.LAUNCH_SINGLE_INSTANCE) {
            //启动源record为singleInstance模式,要重开一个栈
            launchFlags |= Intent.FLAG_ACTIVITY_NEW_TASK;
        } else if (launchSingleInstance || launchSingleTask) {
            //如果目标record为singInstance模式或singleTask模式,也需要重开一个栈
            launchFlags |= Intent.FLAG_ACTIVITY_NEW_TASK;
        }
    }
    ```
    主要工作:确定是否需要为新的`activity`创建一个新的`task`,即是否设置`FLAG_ACTIVITY_NEW_TASK`标志.
    - 第二部分代码
    ```Java
    ActivityInfo newTaskInfo = null;
    Intent newTaskIntent = null;
    ActivityStack sourceStack;
    if (sourceRecord != null) {
        //如果源record存在且已经finish,我们会强制将flag增加成NEW_TASK来创建task
        if (sourceRecord.finishing) {
            if ((launchFlags & Intent.FLAG_ACTIVITY_NEW_TASK) == 0) {
                launchFlags |= Intent.FLAG_ACTIVITY_NEW_TASK;
                newTaskInfo = sourceRecord.info;
                newTaskIntent = sourceRecord.task.intent;
            }
            sourceRecord = null;
            sourceStack = null;
        } else {
            sourceStack = sourceRecord.task.stack;
        }
        boolean movedHome = false;
        ActivityStack targetStack;
        //判断是否有动画
        intent.setFlags(launchFlags);
        final boolean noAnimation = (launchFlags & Intent.FLAG_ACTIVITY_NO_ANIMATION) != 0;
        if (((launchFlags & Intent.FLAG_ACTIVITY_NEW_TASK) != 0 &&
                (launchFlags & Intent.FLAG_ACTIVITY_MULTIPLE_TASK) == 0)
                || launchSingleInstance || launchSingleTask) {
            if (inTask == null && r.resultTo == null) {
                //检查是否有可复用的Task及Activity
                ActivityRecord intentActivity = !launchSingleInstance ?
                    findTaskLocked(r) : findActivityLocked(intent, r.info);
                if (intentActivity != null) {
                    //交换了数据
                    //是否要推送到前台
                    ...
                }
            }
        }
    }
    ```
    主要工作:引出了目标`activity`
    - 第三部分代码
    
    ```Java
    if (r.packageName != null) {
        //判断目标Activity是否已经在栈顶,如果是,需要判断是创建一个新的Activity
        //还是调用onNewIntent(singleTop模式的处理)
        ActivityStack topStack = mFocusedStack;
        ActivityRecord top = topStack.topRunningNonDelayedActivityLocked(notTop);
        if (top != null && r.resultTo == null) {
            ...
        } else {
            ...//通知错误
            return ActivityManager.START_CLASS_NOT_FOUND;
        }
        boolean newTask = false;
        boolean keepCurTransition = false;

        TaskRecord taskToAffiliate = launchTaskBehind && sourceRecord != null ?
                sourceRecord.task : null;
        if (r.resultTo == null && inTask == null && !addingToTask
                && (launchFlags & Intent.FLAG_ACTIVITY_NEW_TASK) != 0) {
            newTask = true;
            //目标stack,一般为mForcusStack
            targetStack = computeStackFocus(r, newTask);
            targetStack.moveToFront("startingNewTask");
            if (reuseTask == null) {
                //ActivityRecord与TaskRecord相关连。  
                //getNextTaskId()方法更新Task数量  
                r.setTask(targetStack.createTaskRecord(getNextTaskId(),
                        newTaskInfo != null ? newTaskInfo : r.info,
                        newTaskIntent != null ? newTaskIntent : intent,
                        voiceSession, voiceInteractor, !launchTaskBehind /* toTop */),
                        taskToAffiliate);
            } else {
                r.setTask(reuseTask, taskToAffiliate);
            }
            if (!movedHome) {
                if ((launchFlags &
                        (FLAG_ACTIVITY_NEW_TASK | FLAG_ACTIVITY_TASK_ON_HOME))
                        == (FLAG_ACTIVITY_NEW_TASK | FLAG_ACTIVITY_TASK_ON_HOME)) {
                        r.task.setTaskToReturnTo(HOME_ACTIVITY_TYPE);
                }
            }
            ...
            //授权控制
             mService.grantUriPermissionFromIntentLocked(callingUid, r.packageName,
                intent, r.getUriPermissionsLocked(), r.userId);
            //放到recent里面去
            if (sourceRecord != null && sourceRecord.isRecentsActivity()) {
                r.task.setTaskToReturnTo(RECENTS_ACTIVITY_TYPE);
            }
            targetStack.mLastPausedActivity = null;
            //ActivityStack 的startActivityLocked函数
            targetStack.startActivityLocked(r, newTask, doResume, keepCurTransition, options);
            return ActivityManager.START_SUCCESS;
    }
    ```
    第三部分工作:得到需要放到哪个`stack`,普通应用为`mForcusStack`,桌面等为`mHomeStack`,创建一个`TaskRecord`,并调用`ActivityStack`的`startActivityLocked`函数进行处理
    `startActivityUncheckedLocked`主要功能:根据启动模式和启动标记,判断是否需要在新的`Task`中启动`Activity`.判断是否有可复用的Task或Activity。将ActivityRecord与TaskRecord关连，更新Task数量，调用startActivityLocked()方法

6. `ActivityStack`的`startActivityLocked`函数

    ```Java
    final void startActivityLocked(ActivityRecord r, boolean newTask,
            boolean doResume, boolean keepCurTransition, Bundle options) {
        TaskRecord rTask = r.task;
        final int taskId = rTask.taskId;
        // mLaunchTaskBehind tasks get placed at the back of the task stack.
        if (!r.mLaunchTaskBehind && (taskForIdLocked(taskId) == null || newTask)) {
            // Last activity in task had been removed or ActivityManagerService is reusing task.
            // Insert or replace.
            // Might not even be in.
            insertTaskAtTop(rTask, r);
            mWindowManager.moveTaskToTop(taskId);
        }
        TaskRecord task = null;
        if (!newTask) {//本例中newTask为true
            ...//找到可以对应的ActivityRecord在task中的位置
        } else if (task.numFullscreen > 0) {
            startIt = false;
        }
        if (task == r.task && mTaskHistory.indexOf(task) != (mTaskHistory.size() - 1)) {
            mStackSupervisor.mUserLeaving = false;
            if (DEBUG_USER_LEAVING) Slog.v(TAG_USER_LEAVING,
                    "startActivity() behind front, mUserLeaving=false");
        }
        //将目标record放在栈顶
        task.addActivityToTop(r);
        task.setFrontOfTask();
        //设置ActivityRecord的inHistory变量为true,表示已经加到mTaskHistory数组中了
        r.putInHistory();
        if (!isHomeStack() || numActivities() > 0) {
            //判断是否显示Activity切换动画之类的事情,需要与WindowManagerService交互
            ...
        }
        ...
        //最终调用resumeTopActivityLocked
        if (doResume) {
            mStackSupervisor.resumeTopActivitiesLocked(this, r, options);
        }
    ```
    - `startActivityLocked`主要功能:根据`newTask`判断是否复用`task`,将`ActivityRecord`放入栈顶,准备`Activity`切换动画,调用`resumeTopActivitiesLocked()`方法
    - 上述代码略去了一部分逻辑处理,这部分内容和`Activity`之间的切换动画有关(通过这些动画,使切换过程看起来更加平滑和美观,需和WMS交互)

7.`ActivityStackSupevisor`的`resumeTopActivitiesLocked`函数

    ```Java
    boolean resumeTopActivitiesLocked(ActivityStack targetStack, ActivityRecord target,
            Bundle targetOptions) {
        if (targetStack == null) {
            targetStack = mFocusedStack;
        }
        // Do targetStack first.
        boolean result = false;
        if (isFrontStack(targetStack)) {
            result = targetStack.resumeTopActivityLocked(target, targetOptions);
        }
        for (int displayNdx = mActivityDisplays.size() - 1; displayNdx >= 0; --displayNdx) {
            final ArrayList<ActivityStack> stacks = mActivityDisplays.valueAt(displayNdx).mStacks;
            for (int stackNdx = stacks.size() - 1; stackNdx >= 0; --stackNdx) {
                final ActivityStack stack = stacks.get(stackNdx);
                if (stack == targetStack) {
                    // Already started above.
                    continue;
                }
                if (isFrontStack(stack)) {
                    stack.resumeTopActivityLocked(null);
                }
            }
        }
        return result;
    }
    ```