# Android系统服务解析
网上很多源码分析都不是6.0的,虽然大致流程一样,但还是有些许不同,所以自己记录下来流程,也更好的理解Android.
## FINISHED:
- AlarmManagerService
- 自启动管理

## ONGOING:
- 权限控制

## TODO:
- PowerManagerService
- ActivityManagerService

## TIPS:
- 修改默认加密手机:修改fstab.in中的flag ~~FLAG_FDE_TYPE~~ /或修改device\mediatek\ [project]\ fstab.{ro.hardware} forceencrypt->encrypt
- 自定义控件属性时:
  ```TypedArray ta = context.obtainStyledAttributes(attrs,R.styleable.TopBar);```
  `obtainStyledAttributes`需要调用两个参数的函数,不然自定义属性不起作用

