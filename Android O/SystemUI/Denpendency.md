# 来源 && 注释:
> Class to handle ugly dependencies throughout sysui until we determine the long-term dependency injection solution. 
> 
> 我们决定使用持久化依赖注入来处理与sysui耦合度较高的类
> 
> Classes added here should be things that are expected to live the lifetime of sysui,and are generally applicable to many parts of sysui. They will be lazily initialized to ensure they aren't created on form factors that don't need them (e.g. HotspotController on TV). Despite being lazily initialized, it is expected that all dependencies will be gotten during sysui startup, and not during runtime to avoid jank.
> 
> 在这里添加的类是和sysui的生命周期相关的,且通常应用在sysui,他们将会被懒加载来保证当他们不需要使用时,他们不会被整体创建(类似HtsoptController on tv)尽管被懒加载,这些也是需要在sysui启动时创建,而不是在运用的时候.
> 
> All classes used here are expected to manage their own lifecycle, meaning if they have no clients they should not have any registered resources like bound services, registered receivers, etc.
> 
> 在这里用到的类是需要有自己的生命周期的 意思是当他们没有任何的clients时他们不应该有任何注册的资源,类似绑定的服务,注册的接收者等

从这个类的注释,我们就可以看出这个类是用来统一注册和管理一些控制器的.
## 重要函数:
从整个类来看,这里主要是将原来QS设置的控制器移到这个类来统一管理,将来扩展和添加都需要在这里进行.
###`OnStart()`
``` Java
@Override
    public void start() {
        sDependency = this; // 保持单例模式
        // TODO: Think about ways to push these creation rules out of Dependency to cut down
        // on imports.
        mProviders.put(TIME_TICK_HANDLER, () -> {
            HandlerThread thread = new HandlerThread("TimeTick");
            thread.start();
            return new Handler(thread.getLooper());
        }); // 注册一个获取time tick广播的handler
        mProviders.put(BG_LOOPER, () -> {
            HandlerThread thread = new HandlerThread("SysUiBg",
                    Process.THREAD_PRIORITY_BACKGROUND);
            thread.start();
            return thread.getLooper();
        }); // 注册一个获取后台工作的looper
        mProviders.put(MAIN_HANDLER, () -> new Handler(Looper.getMainLooper())); // 主线程中的handler
    // 创建一个ActivityStarter单一实例,可以在任何地方被获取到,如果存在就代表着真实实现
        mProviders.put(ActivityStarter.class, () -> new ActivityStarterDelegate());
        mProviders.put(ActivityStarterDelegate.class, () ->
                getDependency(ActivityStarter.class));

        // 传感器管理器的包装器，隐藏潜在的延迟源
        mProviders.put(AsyncSensorManager.class, () ->
                new AsyncSensorManager(mContext.getSystemService(SensorManager.class)));
        
        // 蓝牙控制器
        mProviders.put(BluetoothController.class, () ->
                new BluetoothControllerImpl(mContext, getDependency(BG_LOOPER)));

        // 位置控制器
        mProviders.put(LocationController.class, () ->
                new LocationControllerImpl(mContext, getDependency(BG_LOOPER)));

        // 旋转锁定控制器
        mProviders.put(RotationLockController.class, () ->
                new RotationLockControllerImpl(mContext));

        // 网络控制器
        mProviders.put(NetworkController.class, () ->
                new NetworkControllerImpl(mContext, getDependency(BG_LOOPER),
                        getDependency(DeviceProvisionedController.class)));

        // 勿扰模式控制器
        mProviders.put(ZenModeController.class, () ->
                new ZenModeControllerImpl(mContext, getDependency(MAIN_HANDLER)));
       
        // 热点控制器
        mProviders.put(HotspotController.class, () ->
                new HotspotControllerImpl(mContext));

        // 投屏控制器
        mProviders.put(CastController.class, () ->
                new CastControllerImpl(mContext));

        // 手电筒控制器
        mProviders.put(FlashlightController.class, () ->
                new FlashlightControllerImpl(mContext));

        // 锁屏控制器
        mProviders.put(KeyguardMonitor.class, () ->
                new KeyguardMonitorImpl(mContext));

        // 用户管理控制器
        mProviders.put(UserSwitcherController.class, () ->
                new UserSwitcherController(mContext, getDependency(KeyguardMonitor.class),
                        getDependency(MAIN_HANDLER), getDependency(ActivityStarter.class)));

        // 用户信息控制器
        mProviders.put(UserInfoController.class, () ->
                new UserInfoControllerImpl(mContext));

        // 电池控制器
        mProviders.put(BatteryController.class, () ->
                new BatteryControllerImpl(mContext));

        // 夜间模式控制器
        mProviders.put(NightDisplayController.class, () ->
                new NightDisplayController(mContext));

        // 管理者账户控制器
        mProviders.put(ManagedProfileController.class, () ->
                new ManagedProfileControllerImpl(mContext));

        // 闹钟控制器
        mProviders.put(NextAlarmController.class, () ->
                new NextAlarmControllerImpl(mContext));

        // 数据节省控制器
        mProviders.put(DataSaverController.class, () ->
                get(NetworkController.class).getDataSaverController());// new DataSaverControllerImpl()

        // 无障碍功能控制器
        mProviders.put(AccessibilityController.class, () ->
                new AccessibilityController(mContext));

        // 设备准备控制器
        mProviders.put(DeviceProvisionedController.class, () ->
                new DeviceProvisionedControllerImpl(mContext));

        // 插件管理器
        mProviders.put(PluginManager.class, () ->
                new PluginManagerImpl(mContext));

        // 管理辅助功能
        mProviders.put(AssistManager.class, () ->
                new AssistManager(getDependency(DeviceProvisionedController.class), mContext));

        // 安全控制器
        mProviders.put(SecurityController.class, () ->
                new SecurityControllerImpl(mContext));

        // 内存泄漏检测器
        mProviders.put(LeakDetector.class, LeakDetector::create);

        // 内存泄漏后发送邮件地址
        mProviders.put(LEAK_REPORT_EMAIL, () -> null);

        // 内存泄漏报告
        mProviders.put(LeakReporter.class, () -> new LeakReporter(
                mContext,
                getDependency(LeakDetector.class),
                getDependency(LEAK_REPORT_EMAIL)));

        // 垃圾处理监视
        mProviders.put(GarbageMonitor.class, () -> new GarbageMonitor(
                getDependency(BG_LOOPER),
                getDependency(LeakDetector.class),
                getDependency(LeakReporter.class)));

        // 谐调器
        mProviders.put(TunerService.class, () ->
                new TunerServiceImpl(mContext));

        // 状态栏窗口管理器
        mProviders.put(StatusBarWindowManager.class, () ->
                new StatusBarWindowManager(mContext));

        // 深色图标分发器
        mProviders.put(DarkIconDispatcher.class, () ->
                new DarkIconDispatcherImpl(mContext));

        // 分发配置更改的控制器(像素密度 字体大小 语言地区)
        mProviders.put(ConfigurationController.class, () ->
                new ConfigurationControllerImpl(mContext));

        // 接收commandqueue传来的关于icon的消息,监视icon状态,分发给注册的iconmanager
        mProviders.put(StatusBarIconController.class, () ->
                new StatusBarIconControllerImpl(mContext));
		
		// 监视screen生命周期
        mProviders.put(ScreenLifecycle.class, () ->
                new ScreenLifecycle());

		// 监视亮灭屏生命周期
        mProviders.put(WakefulnessLifecycle.class, () ->
                new WakefulnessLifecycle());

		// 维护FragmentHostStates和config change事件
        mProviders.put(FragmentService.class, () ->
                new FragmentService(mContext));

		// 包括plugin,tuner的默认实现的接口集
        mProviders.put(ExtensionController.class, () ->
                new ExtensionControllerImpl(mContext));
		
		// 用来控制plugins的实现
        mProviders.put(PluginDependencyProvider.class, () ->
                new PluginDependencyProvider(get(PluginManager.class)));
		
		// 提供了一系列蓝牙api
        mProviders.put(LocalBluetoothManager.class, () ->
                LocalBluetoothManager.getInstance(mContext, null));

		// 音量控制器
        mProviders.put(VolumeDialogController.class, () ->
                new VolumeDialogControllerImpl(mContext));

		// log处理
        mProviders.put(MetricsLogger.class, () -> new MetricsLogger());

		// 无障碍原型
        mProviders.put(AccessibilityManagerWrapper.class,
                () -> new AccessibilityManagerWrapper(mContext));

        // Creating a new instance will trigger color extraction.
        // Thankfully this only happens once - during boot - and WallpaperManagerService
        // loads colors from cache.
        mProviders.put(SysuiColorExtractor.class, () -> new SysuiColorExtractor(mContext));

		// 
        mProviders.put(TunablePaddingService.class, () -> new TunablePaddingService());

        mProviders.put(ForegroundServiceController.class,
                () -> new ForegroundServiceControllerImpl(mContext));

        mProviders.put(UiOffloadThread.class, UiOffloadThread::new);

        mProviders.put(PowerUI.WarningsUI.class, () -> new PowerNotificationWarnings(mContext));

        mProviders.put(IconLogger.class, () -> new IconLoggerImpl(mContext,
                getDependency(BG_LOOPER), getDependency(MetricsLogger.class)));

        mProviders.put(LightBarController.class, () -> new LightBarController(mContext));

        mProviders.put(IWindowManager.class, () -> WindowManagerGlobal.getWindowManagerService());

        // Put all dependencies above here so the factory can override them if it wants.
        SystemUIFactory.getInstance().injectDependencies(mProviders, mContext);
    }

```