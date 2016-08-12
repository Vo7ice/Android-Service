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
- `hasOverLapping` 
  自定义 `View` 时重写 `hasOverlappingRendering` 方法指定 `View` 是否有 `Overlapping` 的情况,提高渲染性能.

  ```Java
    @Override
    public boolean hasOverlappingRendering() {
        return false;
    }
  ```
  
-  `View.getLocationInWindow()`和 `View.getLocationOnScreen()`区别
  ```Java
  // location [0]--->x坐标,location [1]--->y坐标
  int[] location = new  int[2];
  // 获取在当前窗口内的绝对坐标,getLeft,getTop,getBottom,getRight 这一组是获取相对在它父窗口里的坐标.
  view.getLocationInWindow(location); 
  // 获取在整个屏幕内的绝对坐标,注意这个值是要从屏幕顶端算起,也就是包括了通知栏的高度.
  view.getLocationOnScreen(location);
  ```
  
  1. 如果在`Activity`的`OnCreate()`事件输出那些参数,是全为0,要等UI控件都加载完了才能获取到这些.在`onWindowFocusChanged(boolean hasFocus)`中获取为好.
  2. `View.getLocationInWindow()`和 `View.getLocationOnScreen()`在`window`占据全部`screen`时,返回值相同.
  不同的典型情况是在`Dialog`中时,当`Dialog`出现在屏幕中间时,`View.getLocationOnScreen()`取得的值要比`View.getLocationInWindow()`取得的值要大

- 给`cardview`加上点击效果(水波纹) `layout`中增加`android:foreground="?attr/selectableItemBackground"` 
  
## Android Studio Tips
  1. 自动导包失效
    清除缓存並重启(`File`-->`Invalidate Cache\Restart...`)

