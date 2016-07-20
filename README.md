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
- 在`onDraw`方法中调用画布`canvas`的`translate`方法将绘制的位置进行平移(+width为左,+height为下)
- 在`LinearGradient`渐变器中

  ```Java
  public LinearGradient(
          float x0,//渐变器x起始线
          float y0,//渐变器y起始线
          float x1,//渐变器x终止线 x1-x0为渐变器宽度
          float y1,//渐变器y终止线 y1-y0为渐变器高度
          int color0,//靠近起始线颜色
          int color1,//靠近终止线颜色
          TileMode tile)//平铺形式 有CLAMP,REPEAT,MIRROR
  ```
  [图像渲染(Shader)](http://www.cnblogs.com/menlsh/archive/2012/12/09/2810372.html)
- 为控件添加触摸水波纹效果,在`style`中配置了`material`主题后在`xml`布局文件中增加属性
  - `android:background="?android:attr/selectableItemBackground"`
  - `android:background="?android:attr/selectableItemBackgroundBorderless"`
  - 为自定义背景添加水波纹效果
    
    ```xml
    <ripple xmlns:android="http://schemas.android.com/apk/res/android"
      android:color="@android:color/white"><!-- 水波纹颜色 必须-->
      <item>
        <!-- 原block-->
      </item>
    </ripple>
    ```
- 给英文设置粗体的方法:
  - 在`xml`中`android:textStyle="bold"`
  - 在代码中,`tv.getPaint().setFakeBoldText(true);`

