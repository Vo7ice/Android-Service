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

从这个类的注释,我们就可以看出