# 作用:
> 通过`predefined`的文件和设备的配置做比较,找出最相近的配置表后配置桌面.

> 同时,准备横屏和竖屏的`DeviceProfile`的文件.

# 重要函数
## `getPredefinedDeviceProfiles`
``` Java
    ArrayList<InvariantDeviceProfile> getPredefinedDeviceProfiles(Context context) {
        ArrayList<InvariantDeviceProfile> profiles = new ArrayList<>();
        try (XmlResourceParser parser = context.getResources().getXml(R.xml.device_profiles)) {
            final int depth = parser.getDepth();
            int type;

            while (((type = parser.next()) != XmlPullParser.END_TAG ||
                    parser.getDepth() > depth) && type != XmlPullParser.END_DOCUMENT) {
                if ((type == XmlPullParser.START_TAG) && "profile".equals(parser.getName())) {
                    TypedArray a = context.obtainStyledAttributes(
                            Xml.asAttributeSet(parser), R.styleable.InvariantDeviceProfile);
                    int numRows = a.getInt(R.styleable.InvariantDeviceProfile_numRows, 0);
                    int numColumns = a.getInt(R.styleable.InvariantDeviceProfile_numColumns, 0);
                    float iconSize = a.getFloat(R.styleable.InvariantDeviceProfile_iconSize, 0);
                    profiles.add(new InvariantDeviceProfile(
                            a.getString(R.styleable.InvariantDeviceProfile_name),
                            a.getFloat(R.styleable.InvariantDeviceProfile_minWidthDps, 0),
                            a.getFloat(R.styleable.InvariantDeviceProfile_minHeightDps, 0),
                            numRows,
                            numColumns,
                            a.getInt(R.styleable.InvariantDeviceProfile_numFolderRows, numRows),
                            a.getInt(R.styleable.InvariantDeviceProfile_numFolderColumns, numColumns),
                            a.getInt(R.styleable.InvariantDeviceProfile_minAllAppsPredictionColumns, numColumns),
                            iconSize,
                            a.getFloat(R.styleable.InvariantDeviceProfile_landscapeIconSize, iconSize),
                            a.getFloat(R.styleable.InvariantDeviceProfile_iconTextSize, 0),
                            a.getInt(R.styleable.InvariantDeviceProfile_numHotseatIcons, numColumns),
                            a.getResourceId(R.styleable.InvariantDeviceProfile_defaultLayoutId, 0),
                            a.getResourceId(R.styleable.InvariantDeviceProfile_demoModeLayoutId, 0)));
                    a.recycle();
                }
            }
        } catch (IOException|XmlPullParserException e) {
            throw new RuntimeException(e);
        }
        return profiles;
    }
```
主要做的事为解析了`device_profiles`文件,里面包含了布局几行几列,文件夹几行几列,几个`hotseat`,默认布局,并创建了多个的对象,为下一步找到最近配置做准备
## `findClosestDeviceProfiles`
``` Java
    ArrayList<InvariantDeviceProfile> findClosestDeviceProfiles(
            final float width, final float height, ArrayList<InvariantDeviceProfile> points) {

        // Sort the profiles by their closeness to the dimensions
        ArrayList<InvariantDeviceProfile> pointsByNearness = points;
        Collections.sort(pointsByNearness, new Comparator<InvariantDeviceProfile>() {
            public int compare(InvariantDeviceProfile a, InvariantDeviceProfile b) {
                // 计算了设备宽高和配置宽高的差值的平方和
                return Float.compare(dist(width, height, a.minWidthDps, a.minHeightDps),
                        dist(width, height, b.minWidthDps, b.minHeightDps));
            }
        });

        return pointsByNearness;
    }
```
主要做的事为通过算法来将数组排序,最接近的排在第一个
## `invDistWeightedInterpolate`
``` Java
    // Package private visibility for testing.
    InvariantDeviceProfile invDistWeightedInterpolate(float width, float height,
                ArrayList<InvariantDeviceProfile> points) {
        float weights = 0;

        InvariantDeviceProfile p = points.get(0);
        // 完全符合直接套用
        if (dist(width, height, p.minWidthDps, p.minHeightDps) == 0) {
            return p;
        }
        // K近似算法和权重来算出指定配置
        InvariantDeviceProfile out = new InvariantDeviceProfile();
        for (int i = 0; i < points.size() && i < KNEARESTNEIGHBOR; ++i) {
            p = new InvariantDeviceProfile(points.get(i));
            float w = weight(width, height, p.minWidthDps, p.minHeightDps, WEIGHT_POWER);
            weights += w;
            out.add(p.multiply(w));
        }
        return out.multiply(1.0f/weights);
    }
```
主要做的事为找到通过k近似算法和权重算出显示`iconSize`,`iconTextSize`,`landscapeIconSize`的尺寸.

## `DeviceProfile`的创建
``` Java
    landscapeProfile = new DeviceProfile(context, this, smallestSize, largestSize, largeSide, 
smallSide, true /* isLandscape */);

    portraitProfile = new DeviceProfile(context, this, smallestSize, largestSize, smallSide, 
largeSide, false /* isLandscape */);
    
    // 根据config来确定返回哪个deviceprofile
    public DeviceProfile getDeviceProfile(Context context) {
        return context.getResources().getConfiguration().orientation
                == Configuration.ORIENTATION_LANDSCAPE ? landscapeProfile : portraitProfile;
    }
```