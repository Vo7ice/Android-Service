# 作用:
> 维护了`Launcher`的多个状态

> 理想状态为单例模式

> 提供了访问`Launcher`数据的`APIs`

# 初始化:
``` Java
    LauncherModel setLauncher(Launcher launcher) {
        getLocalProvider(mContext).setLauncherProviderChangeListener(launcher);// 注册change事件
        mModel.initialize(launcher);// 初始化,且建立和Launcher的交互
        return mModel;
    }
```
