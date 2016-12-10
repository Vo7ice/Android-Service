# 指纹模块相关类
  - `FingerprintService` 一个管理这多个能够和指纹Hal层交互的客户端的服务,维护和掌管这这些客户端和分发事件.
  - `FingerManager` 一个控制着和指纹硬件交互的管理类
  - `Fingerprintd` 初始化Hal层的fingerprint模块,为FingerprintService提供操作指纹的接口;向Hal层注册消息回调函数;向KeystoreService添加认证成功后获取到的auth_token.
  - `FingerprintUnLockController`一个在ui上控制指纹解锁的类
## 注册
  在`SystemServer`启动服务的时候
  ```
  if (mPackageManager.hasSystemFeature(PackageManager.FEATURE_FINGERPRINT)) {
	mSystemServiceManager.startService(FingerprintService.class);
  }
  ```
  判断是否有指纹模块,有的话就启动这个服务.
## 注册管理类
  在`SystemServiceRegister`中会将`FingerprintManager`和`FingerprintService`绑在一起,
  ```
    registerService(Context.FINGERPRINT_SERVICE, FingerprintManager.class,
    	new CachedServiceFetcher<FingerprintManager>() {
	    @Override
	    public FingerprintManager createService(ContextImpl ctx) {
	    	IBinder binder = ServiceManager.getService(Context.FINGERPRINT_SERVICE);
	    	IFingerprintService service = IFingerprintService.Stub.asInterface(binder);
	    return new FingerprintManager(ctx.getOuterContext(), service);
    }});
  ```
  可以通过 `getSystemService`来获得`FingerprintManager`实例
## 沟通HAL层
  在`FingerprintService`注册后会调用`onStart`函数,里面会调用`IFingerprintDaemon daemon = getFingerprintDaemon();`来沟通HAL层.
  看看这个函数做了什么.
  ```
   public IFingerprintDaemon getFingerprintDaemon() {
       if (mDaemon == null) {
		   //获取fingerprintd
           mDaemon = IFingerprintDaemon.Stub.asInterface(ServiceManager.getService(FINGERPRINTD));
           if (mDaemon != null) {
               try {
                   //向fingerprintd注册回调函数mDaemonCallback
                   mDaemon.asBinder().linkToDeath(this, 0);
                   mDaemon.init(mDaemonCallback);
                   //调用获取fingerprintd的openhal函数
                   mHalDeviceId = mDaemon.openHal();
                   if (mHalDeviceId != 0) {
                       /*建立fingerprint文件系统节点，设置节点访问权限，
                         调用fingerprintd的setActiveGroup，
                         将路径传下去。此路径一半用来存储指纹模板的图片等*/
                       updateActiveGroup(ActivityManager.getCurrentUser(), null);
                   } else {
                       Slog.w(TAG, "Failed to open Fingerprint HAL!");
                       mDaemon = null;
                   }
               } catch (RemoteException e) {
                   Slog.e(TAG, "Failed to open fingeprintd HAL", e);
                   mDaemon = null; // try again later!
               }
           } else {
               Slog.w(TAG, "fingerprint service not available");
           }
       }
       return mDaemon;
   }
  ```
### 指纹解锁
  1. 流程
     1. 设置了指纹后,在`KeyguardUpdateMonitor`初始化会去回调监听`fingerprint`函数
     ` private void startListeningForFingerprint() {
            if (mFingerprintRunningState == FINGERPRINT_STATE_CANCELLING) {
                setFingerprintRunningState(FINGERPRINT_STATE_CANCELLING_RESTARTING);
                return;
            }
            if (DEBUG) Log.v(TAG, "startListeningForFingerprint()");
            int userId = ActivityManager.getCurrentUser();
            if (isUnlockWithFingerprintPossible(userId)) {
                if (mFingerprintCancelSignal != null) {
                   mFingerprintCancelSignal.cancel();
                }
                mFingerprintCancelSignal = new CancellationSignal();
				//mFpm为FingerprintManager
                mFpm.authenticate(null, mFingerprintCancelSignal, 0, mAuthenticationCallback, null, userId);
                setFingerprintRunningState(FINGERPRINT_STATE_RUNNING);
            }
        }`
	 2. 传递
	   在`FingerprintManager`中,通过`IFingerprintReceiver`来传递`FingerprintService`发送过来的消息,然后在通过handler传递到callback中;在`KeyguardUPdateMonitor`中,通过`mAuthenticationCallback`把`FingerprintManager`里的消息传递到`keyguard`中,再处理,通过`KeyguardUpdateMonitorCallback`来让具体场景处理问题
  2. 