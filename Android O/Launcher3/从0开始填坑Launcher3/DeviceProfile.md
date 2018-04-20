# 作用:
> `DeviceProfile`中维持了许多的尺寸对象，用来确定`Launcher`中的`Layout`大小.

> 当需要通知`Launcher`需要更新`layout`的时候,也是通过`DeviceProfile`中的接口数组来轮询去通知

# 重要函数:
- `layout(Launcher launcher, boolean notifyListeners)`
``` Java
    public void layout(Launcher launcher, boolean notifyListeners) {
        FrameLayout.LayoutParams lp; // 布局layout
        boolean hasVerticalBarLayout = isVerticalBarLayout();//是否是横屏模式且导航栏在右侧

        // Layout the search bar space
        // 处理QSB的位置
        Point searchBarBounds = getSearchBarDimensForWidgetOpts();
        View searchBar = launcher.getDropTargetBar();
        lp = (FrameLayout.LayoutParams) searchBar.getLayoutParams();
        lp.width = searchBarBounds.x;
        lp.height = searchBarBounds.y;
        lp.topMargin = mInsets.top + edgeMarginPx;
        searchBar.setLayoutParams(lp);

        // Layout the workspace
        // 处理workspace位置
        PagedView workspace = (PagedView) launcher.findViewById(R.id.workspace);
        Rect workspacePadding = getWorkspacePadding(null);
        workspace.setPadding(workspacePadding.left, workspacePadding.top, workspacePadding.right,
                workspacePadding.bottom);
        workspace.setPageSpacing(getWorkspacePageSpacing());

        // Layout the hotseat
        // 处理hotseat
        Hotseat hotseat = (Hotseat) launcher.findViewById(R.id.hotseat);
        lp = (FrameLayout.LayoutParams) hotseat.getLayoutParams();
        // We want the edges of the hotseat to line up with the edges of the workspace, but the
        // icons in the hotseat are a different size, and so don't line up perfectly. To account for
        // this, we pad the left and right of the hotseat with half of the difference of a workspace
        // cell vs a hotseat cell.
        float workspaceCellWidth = (float) getCurrentWidth() / inv.numColumns;
        float hotseatCellWidth = (float) getCurrentWidth() / inv.numHotseatIcons;
        int hotseatAdjustment = Math.round((workspaceCellWidth - hotseatCellWidth) / 2);
        if (hasVerticalBarLayout) {
            // Vertical hotseat -- The hotseat is fixed in the layout to be on the right of the
            //                     screen regardless of RTL
            // 当横屏状态时
            int paddingRight = mInsets.left > 0
                    ? hotseatBarLeftNavBarRightPaddingPx
                    : hotseatBarRightNavBarRightPaddingPx;
            int paddingLeft = mInsets.left > 0
                    ? hotseatBarLeftNavBarLeftPaddingPx
                    : hotseatBarRightNavBarLeftPaddingPx;

            lp.gravity = Gravity.RIGHT;
            lp.width = hotseatBarSizePx + mInsets.left + mInsets.right
                    + paddingLeft + paddingRight;
            lp.height = LayoutParams.MATCH_PARENT;

            hotseat.getLayout().setPadding(mInsets.left + cellLayoutPaddingLeftRightPx
                            + paddingLeft,
                    mInsets.top,
                    mInsets.right + cellLayoutPaddingLeftRightPx + paddingRight,
                    workspacePadding.bottom + cellLayoutBottomPaddingPx);
        } else if (isTablet) {
            // Pad the hotseat with the workspace padding calculated above
            // 当设备是平板时
            lp.gravity = Gravity.BOTTOM;
            lp.width = LayoutParams.MATCH_PARENT;
            lp.height = hotseatBarSizePx + mInsets.bottom;
            hotseat.getLayout().setPadding(hotseatAdjustment + workspacePadding.left
                            + cellLayoutPaddingLeftRightPx,
                    hotseatBarTopPaddingPx,
                    hotseatAdjustment + workspacePadding.right + cellLayoutPaddingLeftRightPx,
                    hotseatBarBottomPaddingPx + mInsets.bottom + cellLayoutBottomPaddingPx);
        } else {
            // For phones, layout the hotseat without any bottom margin
            // to ensure that we have space for the folders
            // 当设备为手机时
            lp.gravity = Gravity.BOTTOM;
            lp.width = LayoutParams.MATCH_PARENT;
            lp.height = hotseatBarSizePx + mInsets.bottom;
            hotseat.getLayout().setPadding(hotseatAdjustment + workspacePadding.left
                            + cellLayoutPaddingLeftRightPx,
                    hotseatBarTopPaddingPx,
                    hotseatAdjustment + workspacePadding.right + cellLayoutPaddingLeftRightPx,
                    hotseatBarBottomPaddingPx + mInsets.bottom + cellLayoutBottomPaddingPx);
        }
        hotseat.setLayoutParams(lp);

        // Layout the page indicators
        // 处理page indicator
        View pageIndicator = launcher.findViewById(R.id.page_indicator);
        if (pageIndicator != null) {
            lp = (FrameLayout.LayoutParams) pageIndicator.getLayoutParams();
            if (isVerticalBarLayout()) {
                if (mInsets.left > 0) {
                    lp.leftMargin = mInsets.left;
                } else {
                    lp.leftMargin = pageIndicatorLandWorkspaceOffsetPx;
                }
                lp.bottomMargin = workspacePadding.bottom;
            } else {
                // Put the page indicators above the hotseat
                lp.gravity = Gravity.CENTER_HORIZONTAL | Gravity.BOTTOM;
                lp.height = pageIndicatorSizePx;
                lp.bottomMargin = hotseatBarSizePx + mInsets.bottom;
            }
            pageIndicator.setLayoutParams(lp);
        }

        // Layout the Overview Mode
        // 处理预览模式
        ViewGroup overviewMode = launcher.getOverviewPanel();
        if (overviewMode != null) {
            int visibleChildCount = getVisibleChildCount(overviewMode);
            int totalItemWidth = visibleChildCount * overviewModeBarItemWidthPx;
            int maxWidth = totalItemWidth + (visibleChildCount - 1) * overviewModeBarSpacerWidthPx;

            lp = (FrameLayout.LayoutParams) overviewMode.getLayoutParams();
            lp.width = Math.min(availableWidthPx, maxWidth);
            lp.height = getOverviewModeButtonBarHeight();
            lp.bottomMargin = mInsets.bottom;
            overviewMode.setLayoutParams(lp);
        }

        // Layout the AllAppsRecyclerView
        // 处理AllApps
        View view = launcher.findViewById(R.id.apps_list_view);
        int paddingLeftRight = desiredWorkspaceLeftRightMarginPx + cellLayoutPaddingLeftRightPx;
        view.setPadding(paddingLeftRight, view.getPaddingTop(), paddingLeftRight,
                view.getPaddingBottom());

        if (notifyListeners) {
            for (int i = mListeners.size() - 1; i >= 0; i--) {
                mListeners.get(i).onLauncherLayoutChanged();
            }
        }
    }
```
在`Launcher`中的`onCreate`中调用后不通知,当用户插入新的图标后,会再调用一次,通知所有接口`update`
``` Java
    public void onInsetsChanged(Rect insets) {
        mDeviceProfile.updateInsets(insets);
        mDeviceProfile.layout(this, true /* notifyListeners */);
    }
```
