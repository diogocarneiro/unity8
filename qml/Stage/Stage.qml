/*
 * Copyright (C) 2014-2016 Canonical, Ltd.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; version 3.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import QtQuick 2.4
import Ubuntu.Components 1.3
import Unity.Application 0.1
import "../Components/PanelState"
import "../Components"
import Utils 0.1
import Ubuntu.Gestures 0.1
import GlobalShortcut 1.0
import "Spread"
import "Spread/MathUtils.js" as MathUtils

AbstractStage {
    id: root
    anchors.fill: parent
    paintBackground: false

    // functions to be called from outside
    function updateFocusedAppOrientation() { /* TODO */ }
    function updateFocusedAppOrientationAnimated() { /* TODO */}
    function pushRightEdge(amount) {
//        if (state === "windowed" || state == "") {
            edgeBarrier.push(amount);
//        }
    }
    function closeFocusedDelegate() {
        if (priv.focusedAppDelegate && !priv.focusedAppDelegate.isDash) {
            priv.focusedAppDelegate.close();
        }
    }

    property string mode: "staged"

    // Used by TutorialRight
    property bool spreadShown: state == "spread"

    mainApp: priv.focusedAppDelegate ? priv.focusedAppDelegate.application : null

    // application windows never rotate independently
    mainAppWindowOrientationAngle: shellOrientationAngle

    orientationChangesEnabled: true

    supportedOrientations: {
        if (mainApp) {
            switch (mode) {
            case "staged":
                return mainApp.supportedOrientations;
            case "stagedWithSideStage":
                var orientations = mainApp.supportedOrientations;
                orientations |= Qt.LandscapeOrientation | Qt.InvertedLandscapeOrientation;
                if (priv.sideStageItemId && !spreadView.surfaceDragging) {
                    // If we have a sidestage app, support Portrait orientation
                    // so that it will switch the sidestage app to mainstage on rotate to portrait
                    orientations |= Qt.PortraitOrientation|Qt.InvertedPortraitOrientation;
                }
                return orientations;
            }
        }

        return Qt.PortraitOrientation |
                Qt.LandscapeOrientation |
                Qt.InvertedPortraitOrientation |
                Qt.InvertedLandscapeOrientation;
    }


    onAltTabPressedChanged: priv.goneToSpread = altTabPressed

    GlobalShortcut {
        id: showSpreadShortcut
        shortcut: Qt.MetaModifier|Qt.Key_W
        onTriggered: state = "altTab"
    }

    GlobalShortcut {
        id: minimizeAllShortcut
        shortcut: Qt.MetaModifier|Qt.ControlModifier|Qt.Key_D
        onTriggered: priv.minimizeAllWindows()
    }

    GlobalShortcut {
        id: maximizeWindowShortcut
        shortcut: Qt.MetaModifier|Qt.ControlModifier|Qt.Key_Up
        onTriggered: priv.focusedAppDelegate.maximize()
        active: priv.focusedAppDelegate !== null
    }

    GlobalShortcut {
        id: maximizeWindowLeftShortcut
        shortcut: Qt.MetaModifier|Qt.ControlModifier|Qt.Key_Left
        onTriggered: priv.focusedAppDelegate.maximizeLeft()
        active: priv.focusedAppDelegate !== null
    }

    GlobalShortcut {
        id: maximizeWindowRightShortcut
        shortcut: Qt.MetaModifier|Qt.ControlModifier|Qt.Key_Right
        onTriggered: priv.focusedAppDelegate.maximizeRight()
        active: priv.focusedAppDelegate !== null
    }

    GlobalShortcut {
        id: minimizeRestoreShortcut
        shortcut: Qt.MetaModifier|Qt.ControlModifier|Qt.Key_Down
        onTriggered: priv.focusedAppDelegate.maximized || priv.focusedAppDelegate.maximizedLeft || priv.focusedAppDelegate.maximizedRight ||
                     priv.focusedAppDelegate.maximizedHorizontally || priv.focusedAppDelegate.maximizedVertically
                     ? priv.focusedAppDelegate.restoreFromMaximized() : priv.focusedAppDelegate.minimize()
        active: priv.focusedAppDelegate !== null
    }

    GlobalShortcut {
        shortcut: Qt.AltModifier|Qt.Key_Print
        onTriggered: root.itemSnapshotRequested(priv.focusedAppDelegate)
        active: priv.focusedAppDelegate !== null
    }

    QtObject {
        id: priv
        objectName: "DesktopStagePrivate"

        property var focusedAppDelegate: null
        onFocusedAppDelegateChanged: {
            if (focusedAppDelegate && root.state == "spread") {
                print("clsing spread because of focus change to", focusedAppDelegate.application.appId)
                goneToSpread = false;
            }
        }

        property var foregroundMaximizedAppDelegate: null // for stuff like drop shadow and focusing maximized app by clicking panel

        property bool goneToSpread: false
        property int closingIndex: -1
//        property int animationDuration: 4000
        property int animationDuration: UbuntuAnimation.FastDuration

        function updateForegroundMaximizedApp() {
            var found = false;
            for (var i = 0; i < appRepeater.count && !found; i++) {
                var item = appRepeater.itemAt(i);
                if (item && item.visuallyMaximized) {
                    foregroundMaximizedAppDelegate = item;
                    found = true;
                }
            }
            if (!found) {
                foregroundMaximizedAppDelegate = null;
            }
        }

        function minimizeAllWindows() {
            for (var i = 0; i < appRepeater.count; i++) {
                var appDelegate = appRepeater.itemAt(i);
                if (appDelegate && !appDelegate.minimized) {
                    appDelegate.minimize();
                }
            }
        }

        function focusNext() {
            for (var i = 0; i < appRepeater.count; i++) {
                var appDelegate = appRepeater.itemAt(i);
                if (appDelegate && !appDelegate.minimized) {
                    print("***** focusing because of focusNext() call", appDelegate.application.appId)
                    appDelegate.focus = true;
                    return;
                }
            }
        }

        property var mainStageDelegate: null
        property var sideStageDelegate: null
        property int mainStageItemId: 0
        property int sideStageItemId: 0
        property string mainStageAppId: ""
        property string sideStageAppId: ""

        onSideStageDelegateChanged: {
            if (!sideStageDelegate) {
                sideStage.hide();
            }
        }

        function updateMainAndSideStageIndexes() {
//            print("updating stage indexes, sideStage shown:", sideStage.shown)
            if (root.mode != "stagedWithSideStage") {
                priv.sideStageDelegate = null;
                priv.sideStageItemId = 0;
                priv.sideStageAppId = "";
                priv.mainStageDelegate = appRepeater.itemAt(0);
                priv.mainStageAppId = topLevelSurfaceList.idAt(0);
                priv.mainStageAppId = topLevelSurfaceList.applicationAt(0) ? topLevelSurfaceList.applicationAt(0).appId : ""
                return;
            }

            var choseMainStage = false;
            var choseSideStage = false;

            if (!root.topLevelSurfaceList)
                return;

            for (var i = 0; i < appRepeater.count && (!choseMainStage || !choseSideStage); ++i) {
                var appDelegate = appRepeater.itemAt(i);
                if (/*sideStage.shown && */appDelegate.stage == ApplicationInfoInterface.SideStage
                        && !choseSideStage) {
                    priv.sideStageDelegate = appDelegate
                    priv.sideStageItemId = root.topLevelSurfaceList.idAt(i);
                    priv.sideStageAppId = root.topLevelSurfaceList.applicationAt(i).appId;
                    choseSideStage = true;
                } else if (!choseMainStage && appDelegate.stage == ApplicationInfoInterface.MainStage) {
                    priv.mainStageDelegate = appDelegate;
                    priv.mainStageItemId = root.topLevelSurfaceList.idAt(i);
                    priv.mainStageAppId = root.topLevelSurfaceList.applicationAt(i).appId;
                    choseMainStage = true;
                }
            }
            if (!choseMainStage) {
                priv.mainStageDelegate = null;
                priv.mainStageItemId = 0;
                priv.mainStageAppId = "";
            }
            if (!choseSideStage) {
                priv.sideStageDelegate = null;
                priv.sideStageItemId = 0;
                priv.sideStageAppId = "";
            }

            print("*** updated! MainStage:", priv.mainStageAppId, "SideStage:", priv.sideStageAppId)
        }

        property int nextInStack: {
            var mainStageIndex = priv.mainStageDelegate ? priv.mainStageDelegate.itemIndex : -1;
            var sideStageIndex = priv.sideStageDelegate ? priv.sideStageDelegate.itemIndex : -1;
//            print("calculating nextInStack:", mainStageIndex, sideStageIndex, priv.mainStageDelegate.itemIndex, priv.sideStageDelegate.itemIndex)
            if (sideStageIndex == -1) {
                return topLevelSurfaceList.count > 1 ? 1 : -1;
            }
            if (mainStageIndex == 0 || sideStageIndex == 0) {
                if (mainStageIndex == 1 || sideStageIndex == 1) {
                    return 2;
                }
                return 1;
            }
            return -1;
        }

        readonly property real virtualKeyboardHeight: SurfaceManager.inputMethodSurface
                                                          ? SurfaceManager.inputMethodSurface.inputBounds.height
                                                          : 0
    }

    Connections {
        target: PanelState
        onCloseClicked: { if (priv.focusedAppDelegate) { priv.focusedAppDelegate.close(); } }
        onMinimizeClicked: { if (priv.focusedAppDelegate) { priv.focusedAppDelegate.minimize(); } }
        onRestoreClicked: { if (priv.focusedAppDelegate) { priv.focusedAppDelegate.restoreFromMaximized(); } }
        onFocusMaximizedApp: {
            if (priv.foregroundMaximizedAppDelegate) {
                print("***** focusing because of Panel request", model.application.appId)
                priv.foregroundMaximizedAppDelegate.focus = true;
             }
        }
    }

    Binding {
        target: PanelState
        property: "buttonsVisible"
        value: priv.focusedAppDelegate !== null && priv.focusedAppDelegate.maximized // FIXME for Locally integrated menus
    }

    Binding {
        target: PanelState
        property: "title"
        value: {
            if (priv.focusedAppDelegate !== null) {
                if (priv.focusedAppDelegate.maximized)
                    return priv.focusedAppDelegate.title
                else
                    return priv.focusedAppDelegate.appName
            }
            return ""
        }
        when: priv.focusedAppDelegate
    }

    Binding {
        target: PanelState
        property: "dropShadow"
        value: priv.focusedAppDelegate && !priv.focusedAppDelegate.maximized && priv.foregroundMaximizedAppDelegate !== null && mode == "windowed"
    }

    Binding {
        target: PanelState
        property: "closeButtonShown"
        value: priv.focusedAppDelegate && priv.focusedAppDelegate.maximized && !priv.focusedAppDelegate.isDash
    }

    Component.onDestruction: {
        PanelState.title = "";
        PanelState.buttonsVisible = false;
        PanelState.dropShadow = false;
    }

    Instantiator {
        model: root.applicationManager
        delegate: QtObject {
            property var stateBinding: Binding {
                readonly property bool isDash: model.application ? model.application.appId == "unity8-dash" : false
                target: model.application
                property: "requestedState"

                // TODO: figure out some lifecycle policy, like suspending minimized apps
                //       or something if running windowed.
                // TODO: If the device has a dozen suspended apps because it was running
                //       in staged mode, when it switches to Windowed mode it will suddenly
                //       resume all those apps at once. We might want to avoid that.
                value: root.mode === "windowed"
                       || (isDash && root.keepDashRunning)
                       || (!root.suspended && model.application && priv.focusedAppDelegate &&
                           (priv.focusedAppDelegate.appId === model.application.appId ||
                            priv.mainStageAppId === model.application.appId ||
                            priv.sideStageAppId === model.application.appId))
                       ? ApplicationInfoInterface.RequestedRunning
                       : ApplicationInfoInterface.RequestedSuspended
            }

            property var lifecycleBinding: Binding {
                target: model.application
                property: "exemptFromLifecycle"
                value: model.application
                            ? (!model.application.isTouchApp || isExemptFromLifecycle(model.application.appId))
                            : false
            }
        }
    }

    Binding {
        target: MirFocusController
        property: "focusedSurface"
        value: priv.focusedAppDelegate ? priv.focusedAppDelegate.focusedSurface : null
        when: !appRepeater.startingUp && root.parent
    }

    states: [
        State {
            name: "spread"; when: priv.goneToSpread
            PropertyChanges { target: floatingFlickable; enabled: true }
            PropertyChanges { target: spreadItem; focus: true }
            PropertyChanges { target: hoverMouseArea; enabled: true }
        },
        State {
            name: "stagedRightEdge"; when: (rightEdgeDragArea.dragging || edgeBarrier.progress > 0) && root.mode == "staged"
        },
        State {
            name: "sideStagedRightEdge"; when: (rightEdgeDragArea.dragging || edgeBarrier.progress > 0) && root.mode == "stagedWithSideStage"
//            PropertyChanges { target: priv; nextInStack: priv.sideStageDelegate && priv.sideStageDelegate.itemIndex < 2 ? 2 : 1 }
        },
        State {
            name: "windowedRightEdge"; when: (rightEdgeDragArea.dragging || edgeBarrier.progress > 0) && root.mode == "windowed"
        },
        State {
            name: "staged"; when: root.mode === "staged"
        },
        State {
            name: "stagedWithSideStage"; when: root.mode === "stagedWithSideStage"
            PropertyChanges { target: triGestureArea; enabled: true }
//            PropertyChanges { target: priv; nextInStack: priv.sideStageDelegate && priv.sideStageDelegate.itemIndex < 2 ? 2 : 1 }
            PropertyChanges { target: sideStage; visible: true }
        },
        State {
            name: "windowed"; when: root.mode === "windowed"
        }
    ]
    transitions: [
        Transition {
            from: "stagedRightEdge,sideStagedRightEdge,windowedRightEdge"; to: "spread"
            PropertyAction { target: spreadItem; property: "highlightedIndex"; value: -1 }
        },
        Transition {
            to: "spread"
            PropertyAction { target: spreadItem; property: "highlightedIndex"; value: appRepeater.count > 1 ? 1 : 0 }
            PropertyAction { target: floatingFlickable; property: "contentX"; value: 0 }
        },
        Transition {
            from: "spread"
            SequentialAnimation {
                ScriptAction {
                    script: {
                        print("hightedIndex is:", spreadItem.highlightedIndex)
                        var item = appRepeater.itemAt(Math.max(0, spreadItem.highlightedIndex));
                        print("playing focus animation 3 on item", spreadItem.highlightedIndex, item.application.appId)

                        item.playFocusAnimation();
                    }
                }
                PropertyAction { target: spreadItem; property: "highlightedIndex"; value: -1 }
            }
        },
        Transition {
            to: "stagedRightEdge"
            PropertyAction { target: floatingFlickable; property: "contentX"; value: 0 }
        }

    ]

    FocusScope {
        id: appContainer
        objectName: "appContainer"
        anchors.fill: parent
        focus: root.state !== "altTab"

        CrossFadeImage {
            id: wallpaper
            anchors.fill: parent
            source: root.background
            sourceSize { height: root.height; width: root.width }
            fillMode: Image.PreserveAspectCrop
        }

        Spread {
            id: spreadItem
            objectName: "spreadItem"
            anchors.fill: appContainer
            leftMargin: root.leftMargin
            model: root.topLevelSurfaceList
            z: 10

            onLeaveSpread: {
                priv.goneToSpread = false;
            }
        }

        Connections {
            target: root.topLevelSurfaceList
            onListChanged: priv.updateMainAndSideStageIndexes()
        }


        DropArea {
            objectName: "MainStageDropArea"
            anchors {
                left: parent.left
                top: parent.top
                bottom: parent.bottom
            }
            width: appContainer.width - sideStage.width
            enabled: sideStage.enabled

            onDropped: {
                print("dropped on main stage drop area")
                drop.source.appDelegate.saveStage(ApplicationInfoInterface.MainStage);
                drop.source.appDelegate.focus = true;
            }
            keys: "SideStage"
        }

        SideStage {
            id: sideStage
            shown: false
            height: appContainer.height
            x: appContainer.width - width
            visible: false
            z: {
                if (!priv.mainStageItemId) return 0;

                if (priv.sideStageItemId && priv.nextInStack > 0) {
                    var nextDelegateInStack = appRepeater.itemAt(priv.nextInStack);

                    if (nextDelegateInStack.stage ===  ApplicationInfoInterface.MainStage) {
                        // if the next app in stack is a main stage app, put the sidestage on top of it.
                        return 2;
                    }
                    return 1;
                }

                return 2;
            }

            onShownChanged: {
                print("sidestage shown changed:", shown)
                if (!shown && priv.mainStageDelegate) {
                    print("claiming focus 2")
                    priv.mainStageDelegate.claimFocus();
                }
            }

//            onShownChanged: {
//                if (!shown && priv.sideStageDelegate && priv.focusedAppDelegate === priv.sideStageDelegate) {
//                    priv.updateMainAndSideStageIndexes();
//                    if (priv.mainStageDelegate) {
//                        priv.mainStageDelegate.focus = true;
//                    }
//                } else if (shown) {
//                    priv.updateMainAndSideStageIndexes();
//                    if (priv.sideStageDelegate) {
//                        priv.sideStageDelegate.focus = true;
//                    }
//                }
//            }

            DropArea {
                id: sideStageDropArea
                objectName: "SideStageDropArea"
                anchors.fill: parent

                property bool dropAllowed: true

                onEntered: {
                    dropAllowed = drag.keys != "Disabled";
                }
                onExited: {
                    dropAllowed = true;
                }
                onDropped: {
                    if (drop.keys == "MainStage") {
                        drop.source.appDelegate.saveStage(ApplicationInfoInterface.SideStage);
                        print("dropped on mainstage")
                        drop.source.appDelegate.focus = true;
                    }
                }
                drag {
                    onSourceChanged: {
                        if (!sideStageDropArea.drag.source) {
                            dropAllowed = true;
                        }
                    }
                }
            }
        }

        TopLevelSurfaceRepeater {
            id: appRepeater
            model: topLevelSurfaceList
            objectName: "appRepeater"

            delegate: FocusScope {
                id: appDelegate
                objectName: "appDelegate_" + model.id
                property int itemIndex: index // We need this from outside the repeater
                // z might be overriden in some cases by effects, but we need z ordering
                // to calculate occlusion detection
                property int normalZ: topLevelSurfaceList.count - index
                onNormalZChanged: {
                    if (visuallyMaximized) {
                        priv.updateForegroundMaximizedApp();
                    }
                }
                z: normalZ

                // Normally we want x/y where we request it to be. Width/height of our delegate will
                // match what the actual surface size is.
                // Don't write to those, they will be set by states
                x: requestedX
                y: requestedY
                width: decoratedWindow.implicitWidth
                height: decoratedWindow.implicitHeight

                // requestedX/Y/width/height is what we ask the actual surface to be.
                // Do not write to those, they will be set by states
                property real requestedX: 0
                property real requestedY: 0
                property int requestedWidth: -1
                property int requestedHeight: -1

                // In those are for windowed mode. Those values basically store the window's properties
                // when having a floating window. If you want to move/resize a window in normal mode, this is what you want to write to.
                property int windowedX: priv.focusedAppDelegate ? priv.focusedAppDelegate.x + units.gu(3) : (normalZ - 1) * units.gu(3)
                property int windowedY: priv.focusedAppDelegate ? priv.focusedAppDelegate.y + units.gu(3) : normalZ * units.gu(3)
                property int windowedWidth
                property int windowedHeight

                Binding {
                    target: appDelegate
                    property: "y"
                    value: appDelegate.requestedY -
                           Math.min(appDelegate.requestedY - PanelState.panelHeight,
                                    Math.max(0, priv.virtualKeyboardHeight - (appContainer.height - (appDelegate.requestedY + appDelegate.height))))
                    when: root.oskEnabled && appDelegate.focus && appDelegate.state == "normal"
                          && SurfaceManager.inputMethodSurface
                          && SurfaceManager.inputMethodSurface.state != Mir.HiddenState
                          && SurfaceManager.inputMethodSurface.state != Mir.MinimizedState

                }

                Behavior on x { id: xBehavior; enabled: priv.closingIndex >= 0; UbuntuNumberAnimation { onRunningChanged: if (!running) priv.closingIndex = -1} }

                Connections {
                    target: root
                    onShellOrientationAngleChanged: {
                        // at this point decoratedWindow.surfaceOrientationAngle is the old shellOrientationAngle
                        if (application && application.rotatesWindowContents) {
                            if (state == "normal") {
                                var angleDiff = decoratedWindow.surfaceOrientationAngle - shellOrientationAngle;
                                angleDiff = (360 + angleDiff) % 360;
                                if (angleDiff === 90 || angleDiff === 270) {
                                    var aux = decoratedWindow.requestedHeight;
                                    decoratedWindow.requestedHeight = decoratedWindow.requestedWidth + decoratedWindow.visibleDecorationHeight;
                                    decoratedWindow.requestedWidth = aux - decoratedWindow.visibleDecorationHeight;
                                }
                            }
                            decoratedWindow.surfaceOrientationAngle = shellOrientationAngle;
                        } else {
                            decoratedWindow.surfaceOrientationAngle = 0;
                        }
                    }
                }

                readonly property alias application: decoratedWindow.application
                readonly property alias minimumWidth: decoratedWindow.minimumWidth
                readonly property alias minimumHeight: decoratedWindow.minimumHeight
                readonly property alias maximumWidth: decoratedWindow.maximumWidth
                readonly property alias maximumHeight: decoratedWindow.maximumHeight
                readonly property alias widthIncrement: decoratedWindow.widthIncrement
                readonly property alias heightIncrement: decoratedWindow.heightIncrement

                readonly property bool maximized: windowState & WindowStateStorage.WindowStateMaximized
                readonly property bool maximizedLeft: windowState & WindowStateStorage.WindowStateMaximizedLeft
                readonly property bool maximizedRight: windowState & WindowStateStorage.WindowStateMaximizedRight
                readonly property bool maximizedHorizontally: windowState & WindowStateStorage.WindowStateMaximizedHorizontally
                readonly property bool maximizedVertically: windowState & WindowStateStorage.WindowStateMaximizedVertically
                readonly property bool minimized: windowState & WindowStateStorage.WindowStateMinimized
                readonly property bool fullscreen: surface && surface.state === Mir.FullscreenState;

                property int windowState: WindowStateStorage.WindowStateNormal
                property bool animationsEnabled: true
                property alias title: decoratedWindow.title
                readonly property string appName: model.application ? model.application.name : ""
                property bool visuallyMaximized: false
                property bool visuallyMinimized: false

                property int stage: ApplicationInfoInterface.MainStage
                function saveStage(newStage) {
                    appDelegate.stage = newStage;
                    WindowStateStorage.saveStage(application.appId, newStage);
                    priv.updateMainAndSideStageIndexes()
                }

                readonly property var surface: model.surface
                readonly property alias resizeArea: resizeArea
                readonly property alias focusedSurface: decoratedWindow.focusedSurface

                readonly property string appId: model.application.appId
                readonly property bool isDash: model.application.appId == "unity8-dash"

                function claimFocus() {
                    print("(claimfocus) focusing app", priv.sideStageDelegate, appDelegate, sideStage.shown)
                    if (root.mode == "windowed" && minimized) {
                        restore(true)
                    }
                    if (appDelegate.stage == ApplicationInfoInterface.SideStage && !sideStage.shown) {
                        sideStage.show();
                    }
                    appDelegate.focus = true;
                }
                Connections {
                    target: model.surface
                    onFocusRequested: {
                        // Reset spread selection in case there is any
                        spreadItem.highlightedIndex = -1
                        print("claiming focus 3")
                        claimFocus();
                    }
                }
                Connections {
                    target: model.application
                    onFocusRequested: {
                        if (!model.surface) {
                            // when an app has no surfaces, we assume there's only one entry representing it:
                            // this delegate.
                            print("claiming focus 4")
                            claimFocus();
                        } else {
                            // if the application has surfaces, focus request should be at surface-level.
                        }
                    }
                }

                onFocusChanged: {
                    if (appRepeater.startingUp)
                        return;

                    if (focus) {
                        topLevelSurfaceList.raiseId(model.id);
                        priv.focusedAppDelegate = appDelegate;
                        topLevelSurfaceList.raiseId(model.id);
                    } else if (!focus && priv.focusedAppDelegate === appDelegate) {
                        priv.focusedAppDelegate = null;
                        // FIXME: No idea why the Binding{} doens't update when focusedAppDelegate turns null
                        MirFocusController.focusedSurface = null;
                    }
                }
                Component.onCompleted: {
                    if (application && application.rotatesWindowContents) {
                        decoratedWindow.surfaceOrientationAngle = shellOrientationAngle;
                    } else {
                        decoratedWindow.surfaceOrientationAngle = 0;
                    }

                    // NB: We're differentiating if this delegate was created in response to a new entry in the model
                    //     or if the Repeater is just populating itself with delegates to match the model it received.
                    if (!appRepeater.startingUp) {
                        // a top level window is always the focused one when it first appears, unfocusing
                        // any preexisting one
                        print("focusing because of creation")
                        focus = true;
                    }
                }
                Component.onDestruction: {
                    if (!root.parent) {
                        // This stage is about to be destroyed. Don't mess up with the model at this point
                        return;
                    }

                    if (visuallyMaximized) {
                        priv.updateForegroundMaximizedApp();
                    }

                    if (focus) {
                        // focus some other window
                        for (var i = 0; i < appRepeater.count; i++) {
                            var appDelegate = appRepeater.itemAt(i);
                            if (appDelegate && !appDelegate.minimized && i != index) {
                                print("focusing some other because of destruction")
                                appDelegate.focus = true;
                                return;
                            }
                        }
                    }
                }

                onVisuallyMaximizedChanged: priv.updateForegroundMaximizedApp()

                onStageChanged: {
                    if (!_constructing) {
                        priv.updateMainAndSideStageIndexes();
                    }
                }

//                visible: (
//                          !visuallyMinimized
//                          && !greeter.fullyShown
//                          && (priv.foregroundMaximizedAppDelegate === null || priv.foregroundMaximizedAppDelegate.normalZ <= z)
//                         )
//                         || decoratedWindow.fullscreen
//                       //  || (root.state == "altTab" && index === spread.highlightedIndex)

                function close() {
                    model.surface.close();
                }

                function maximize(animated) {
                    animationsEnabled = (animated === undefined) || animated;
                    windowState = WindowStateStorage.WindowStateMaximized;
                }
                function maximizeLeft(animated) {
                    animationsEnabled = (animated === undefined) || animated;
                    windowState = WindowStateStorage.WindowStateMaximizedLeft;
                }
                function maximizeRight(animated) {
                    animationsEnabled = (animated === undefined) || animated;
                    windowState = WindowStateStorage.WindowStateMaximizedRight;
                }
                function maximizeHorizontally(animated) {
                    animationsEnabled = (animated === undefined) || animated;
                    windowState = WindowStateStorage.WindowStateMaximizedHorizontally;
                }
                function maximizeVertically(animated) {
                    animationsEnabled = (animated === undefined) || animated;
                    windowState = WindowStateStorage.WindowStateMaximizedVertically;
                }
                function minimize(animated) {
                    animationsEnabled = (animated === undefined) || animated;
                    windowState |= WindowStateStorage.WindowStateMinimized; // add the minimized bit
                }
                function restoreFromMaximized(animated) {
                    animationsEnabled = (animated === undefined) || animated;
                    windowState = WindowStateStorage.WindowStateNormal;
                }
                function restore(animated) {
                    animationsEnabled = (animated === undefined) || animated;
                    windowState &= ~WindowStateStorage.WindowStateMinimized; // clear the minimized bit
                    if (maximized)
                        maximize();
                    else if (maximizedLeft)
                        maximizeLeft();
                    else if (maximizedRight)
                        maximizeRight();
                    else if (maximizedHorizontally)
                        maximizeHorizontally();
                    else if (maximizedVertically)
                        maximizeVertically();

                    print("***** focusing because of window restore", model.application.appId)
                    focus = true;
                }

                function playFocusAnimation() {
                    print("playing focus animation", state, root.mode, "app", model.application.appId)
                    if (state == "stagedRightEdge") {
                        // TODO: Can we drop this if and find something that always works?
                        if (root.mode == "staged") {
                            rightEdgeFocusAnimation.targetX = 0
                            print("doing it to 0")
                            rightEdgeFocusAnimation.start()
                        } else if (root.mode == "stagedWithSideStage") {
                            rightEdgeFocusAnimation.targetX = appDelegate.stage == ApplicationInfoInterface.SideStage ? sideStage.x : 0
                            rightEdgeFocusAnimation.start()
                        }
                    } else if (state == "windowedRightEdge") {
                        print("claiming focus 1")
                        claimFocus();
                    } else {
                        focusAnimation.start()
                    }
                }
                function playHidingAnimation() {
                    if (state != "windowedRightEdge") {
                        hidingAnimation.start()
                    }
                }

                UbuntuNumberAnimation {
                    id: focusAnimation
                    target: appDelegate
                    property: "scale"
                    from: 0.98
                    to: 1
                    duration: UbuntuAnimation.SnapDuration
                    onStarted: {
                        print("starting focusanimation for", model.application.appId)
                        topLevelSurfaceList.raiseId(model.id);
                    }
                    onStopped: {
                        print("focusing because of normal focus animation finishing")
                        appDelegate.focus = true
                    }
                }
                ParallelAnimation {
                    id: rightEdgeFocusAnimation
                    property int targetX: 0
                    onStarted: print("starting rightedgefocusanimation for", model.application.appId)
                    UbuntuNumberAnimation { target: appDelegate; properties: "x"; to: rightEdgeFocusAnimation.targetX; duration: priv.animationDuration }
                    UbuntuNumberAnimation { target: decoratedWindow; properties: "angle"; to: 0; duration: priv.animationDuration }
                    UbuntuNumberAnimation { target: decoratedWindow; properties: "itemScale"; to: 1; duration: priv.animationDuration }
                    onStopped: {
                        print("focusing", model.application.appId, "because of right edge focus animation completion");
                        appDelegate.focus = true
                    }
                }
                ParallelAnimation {
                    id: hidingAnimation
                    onStarted: print("starting hiding animation for", model.application.appId)
                    UbuntuNumberAnimation { target: appDelegate; property: "opacity"; to: 0; duration: priv.animationDuration }
                    onStopped: appDelegate.opacity = 1
                }

                SpreadMaths {
                    id: spreadMaths
                    spread: spreadItem
                    itemIndex: index
                    flickable: floatingFlickable
                }
                StageMaths {
                    id: stageMaths
                    sceneWidth: root.width
                    stage: appDelegate.stage
                    thisDelegate: appDelegate
                    mainStageDelegate: priv.mainStageDelegate
                    sideStageDelegate: priv.sideStageDelegate
                    sideStageWidth: sideStage.panelWidth
                    sideStageX: sideStage.x
                    itemIndex: appDelegate.itemIndex
                    nextInStack: priv.nextInStack
                }

                StagedRightEdgeMaths {
                    id: stagedRightEdgeMaths
                    sceneWidth: appContainer.width - root.leftMargin
                    sceneHeight: appContainer.height
                    isMainStageApp: priv.mainStageDelegate == appDelegate
                    isSideStageApp: priv.sideStageDelegate == appDelegate
                    sideStageWidth: sideStage.width
                    itemIndex: index
                    nextInStack: priv.nextInStack
                    progress: 0
                    targetHeight: spreadItem.stackHeight
                    targetX: spreadMaths.targetX
                    startY: appDelegate.fullscreen ? 0 : PanelState.panelHeight
                    targetY: spreadMaths.targetY
                    targetAngle: spreadMaths.targetAngle
                    targetScale: spreadMaths.targetScale
                    shuffledZ: stageMaths.itemZ
                    breakPoint: spreadItem.rightEdgeBreakPoint
                }

                WindowedRightEdgeMaths {
                    id: windowedRightEdgeMaths
                    itemIndex: index
                    startWidth: appDelegate.requestedWidth
                    startHeight: appDelegate.requestedHeight
                    targetHeight: spreadItem.stackHeight
                    targetX: spreadMaths.targetX
                    targetY: spreadMaths.targetY
                    normalZ: appDelegate.normalZ
                    targetAngle: spreadMaths.targetAngle
                    targetScale: spreadMaths.targetScale
                    breakPoint: spreadItem.rightEdgeBreakPoint
                }

                states: [
                    State {
                        name: "spread"; when: root.state == "spread"
                        PropertyChanges {
                            target: decoratedWindow;
                            showDecoration: false;
                            angle: spreadMaths.targetAngle
                            itemScale: spreadMaths.targetScale
                            scaleToPreviewSize: spreadItem.stackHeight
                            scaleToPreviewProgress: 1
                            hasDecoration: root.mode === "windowed"
                            shadowOpacity: spreadMaths.shadowOpacity
                            showHighlight: spreadItem.highlightedIndex === index
                            darkening: spreadItem.highlightedIndex >= 0
                            anchors.topMargin: dragArea.distance
                        }
                        PropertyChanges {
                            target: appDelegate
                            x: spreadMaths.targetX
                            y: spreadMaths.targetY
                            z: index
                            height: spreadItem.spreadItemHeight
                            requestedWidth: decoratedWindow.oldRequestedWidth
                            requestedHeight: decoratedWindow.oldRequestedHeight
                            visible: spreadMaths.itemVisible
                        }
                        PropertyChanges { target: dragArea; enabled: true }
                        PropertyChanges { target: windowInfoItem; opacity: spreadMaths.tileInfoOpacity; visible: spreadMaths.itemVisible }
                    },
                    State {
                        name: "stagedRightEdge"
                        when: (root.mode == "staged" || root.mode == "stagedWithSideStage") && (root.state == "sideStagedRightEdge" || root.state == "stagedRightEdge" || rightEdgeFocusAnimation.running || hidingAnimation.running)
                        PropertyChanges {
                            target: stagedRightEdgeMaths
                            progress: Math.max(edgeBarrier.progress, rightEdgeDragArea.progress)
                        }
                        PropertyChanges {
                            target: appDelegate
                            x: stagedRightEdgeMaths.animatedX
                            y: stagedRightEdgeMaths.animatedY
                            z: stagedRightEdgeMaths.animatedZ
                            height: stagedRightEdgeMaths.animatedHeight
                            requestedWidth: decoratedWindow.oldRequestedWidth
                            requestedHeight: decoratedWindow.oldRequestedHeight
                        }
                        PropertyChanges {
                            target: decoratedWindow
                            hasDecoration: false
                            angle: stagedRightEdgeMaths.animatedAngle
                            itemScale: stagedRightEdgeMaths.animatedScale
                            scaleToPreviewSize: spreadItem.stackHeight
                            scaleToPreviewProgress: stagedRightEdgeMaths.scaleToPreviewProgress
                            shadowOpacity: .3
                        }
                    },
                    State {
                        name: "windowedRightEdge"
                        when: root.mode == "windowed" && (root.state == "windowedRightEdge" || rightEdgeFocusAnimation.running || hidingAnimation.running || edgeBarrier.progress > 0)
                        PropertyChanges {
                            target: windowedRightEdgeMaths
                            progress: Math.max(rightEdgeDragArea.progress, edgeBarrier.progress)
                        }
                        PropertyChanges {
                            target: appDelegate
                            x: windowedRightEdgeMaths.animatedX
                            y: windowedRightEdgeMaths.animatedY
                            z: windowedRightEdgeMaths.animatedZ
                            height: stagedRightEdgeMaths.animatedHeight
                            requestedWidth: decoratedWindow.oldRequestedWidth
                            requestedHeight: decoratedWindow.oldRequestedHeight
                        }
                        PropertyChanges {
                            target: decoratedWindow
                            showDecoration: windowedRightEdgeMaths.decorationHeight
                            angle: windowedRightEdgeMaths.animatedAngle
                            itemScale: windowedRightEdgeMaths.animatedScale
                            scaleToPreviewSize: spreadItem.stackHeight
                            scaleToPreviewProgress: windowedRightEdgeMaths.scaleToPreviewProgress
                            shadowOpacity: .3
                        }
                        PropertyChanges {
                            target: opacityEffect;
                            opacityValue: windowedRightEdgeMaths.opacityMask
                            sourceItem: windowedRightEdgeMaths.opacityMask < 1 ? decoratedWindow : null
                        }
                    },
                    State {
                        name: "staged"; when: root.state == "staged"
                        PropertyChanges {
                            target: appDelegate
                            x: appDelegate.itemIndex == 0 ? 0 : root.width
                            y: appDelegate.fullscreen ? 0 : PanelState.panelHeight
                            requestedWidth: appContainer.width
                            requestedHeight: appDelegate.fullscreen ? appContainer.height : appContainer.height - PanelState.panelHeight
                            visuallyMaximized: true
                            visible: appDelegate.itemIndex == 0
                        }
                        PropertyChanges {
                            target: decoratedWindow
                            hasDecoration: false
                        }
                        PropertyChanges {
                            target: resizeArea
                            enabled: false
                        }
                    },
                    State {
                        name: "stagedWithSideStage"; when: root.state == "stagedWithSideStage"
                        PropertyChanges {
                            target: stageMaths
                            itemIndex: index
                        }
                        PropertyChanges {
                            target: appDelegate
                            x: stageMaths.itemX
                            y: appDelegate.fullscreen ? 0 : PanelState.panelHeight
                            z: stageMaths.itemZ
                            requestedWidth: stageMaths.itemWidth
                            requestedHeight: appDelegate.fullscreen ? appContainer.height : appContainer.height - PanelState.panelHeight
                            visuallyMaximized: true
                        }
                        PropertyChanges {
                            target: decoratedWindow
                            hasDecoration: false
                        }
                        PropertyChanges {
                            target: resizeArea
                            enabled: false
                        }
                    },
                    State {
                        name: "maximized"; when: root.state === "windowed" && appDelegate.maximized && !appDelegate.minimized
                        PropertyChanges {
                            target: appDelegate;
                            requestedX: root.leftMargin;
                            requestedY: 0;
                            visuallyMinimized: false;
                            visuallyMaximized: true
                            requestedWidth: appContainer.width - root.leftMargin;
                            requestedHeight: appContainer.height;
                        }
                    },
                    State {
                        name: "fullscreen"; when: surface ? surface.state === Mir.FullscreenState : application.fullscreen && !appDelegate.minimized
                        PropertyChanges {
                            target: appDelegate;
                            requestedX: rotation == 0 ? 0 : (parent.width - width) / 2 + (shellOrientationAngle == 90 ? 0 : PanelState.panelHeight)
                            requestedY: rotation == 0 ? 0 : (parent.height - height) / 2
                            requestedWidth: appContainer.width;
                            requestedHeight: appContainer.height;
                        }
                        PropertyChanges { target: decoratedWindow; hasDecoration: false }
                    },
                    State {
                        name: "normal";
                        when: appDelegate.windowState == WindowStateStorage.WindowStateNormal
                        PropertyChanges {
                            target: appDelegate
                            visuallyMinimized: false
                            visuallyMaximized: false
                            requestedX: appDelegate.windowedX
                            requestedY: appDelegate.windowedY
                            requestedWidth: appDelegate.windowedWidth
                            requestedHeight: appDelegate.windowedHeight
                        }
                        PropertyChanges { target: touchControls; enabled: true }
                        PropertyChanges { target: resizeArea; enabled: true }
                        PropertyChanges { target: decoratedWindow; shadowOpacity: .3}
                    },
                    State {
                        name: "maximizedLeft"; when: appDelegate.maximizedLeft && !appDelegate.minimized
                        PropertyChanges {
                            target: appDelegate
                            requestedX: root.leftMargin
                            requestedY: PanelState.panelHeight
                            requestedWidth: (appContainer.width - root.leftMargin)/2
                            requestedHeight: appContainer.height - PanelState.panelHeight
                        }
                        PropertyChanges {
                            target: decoratedWindow
                            shadowOpacity: .3
                        }
                    },
                    State {
                        name: "maximizedRight"; when: appDelegate.maximizedRight && !appDelegate.minimized
                        PropertyChanges {
                            target: appDelegate;
                            requestedX: (appContainer.width + root.leftMargin)/2
                            requestedY: PanelState.panelHeight
                            requestedWidth: (appContainer.width - root.leftMargin)/2
                            requestedHeight: appContainer.height - PanelState.panelHeight
                        }
                        PropertyChanges {
                            target: decoratedWindow
                            shadowOpacity: .3
                        }
                    },
                    State {
                        name: "maximizedHorizontally"; when: appDelegate.maximizedHorizontally && !appDelegate.minimized
                        PropertyChanges {
                            target: appDelegate;
                            requestedX: root.leftMargin
                            requestedY: appDelegate.windowedY
                            requestedWidth: appContainer.width - root.leftMargin
                            requestedHeight: appDelegate.windowedHeight
                        }
                        PropertyChanges {
                            target: decoratedWindow;
                            shadowOpacity: .3
                        }
                    },
                    State {
                        name: "maximizedVertically"; when: appDelegate.maximizedVertically && !appDelegate.minimized
                        PropertyChanges {
                            target: appDelegate;
                            requestedX: appDelegate.windowedX
                            requestedY: PanelState.panelHeight
                            requestedWidth: appDelegate.windowedWidth
                            requestedHeight: appContainer.height - PanelState.panelHeight
                        }
                        PropertyChanges {
                            target: decoratedWindow;
                            shadowOpacity: .3
                        }
                    },
                    State {
                        name: "minimized"; when: appDelegate.minimized
                        PropertyChanges {
                            target: appDelegate
                            requestedWidth: decoratedWindow.oldRequestedWidth
                            requestedHeight: decoratedWindow.oldRequestedHeight
                            x: -appDelegate.width / 2;
                            y: requestedY // TODO: Should be where the icon is in the launcher. Lets just move it horizontally to the left for now.
                            scale: units.gu(5) / appDelegate.width
                            opacity: 0;
                            visuallyMinimized: true
                            visuallyMaximized: false
                        }
                    }

                ]
                transitions: [
                    Transition {
                        from: "staged,stagedWithSideStage"; to: "normal"
                        enabled: appDelegate.animationsEnabled
                        PropertyAction { target: appDelegate; properties: "visuallyMinimized,visuallyMaximized" }
                        UbuntuNumberAnimation { target: appDelegate; properties: "x,y,opacity,requestedWidth,requestedHeight,scale"; duration: priv.animationDuration }
                    },
                    Transition {
                        from: "maximized,maximizedHorizontally,maximizedVertically,maximizedLeft,maximizedRight,minimized"; to: "normal"
                        enabled: appDelegate.animationsEnabled
                        PropertyAction { target: appDelegate; properties: "visuallyMinimized,visuallyMaximized" }
                        UbuntuNumberAnimation { target: appDelegate; properties: "x,y,requestedWidth,requestedHeight,scale"; duration: priv.animationDuration }
                    },
                    Transition {
                        from: "normal"; to: "maximized,maximizedHorizontally,maximizedVertically,maximizedLeft,maximizedRight"
                        enabled: appDelegate.animationsEnabled
                        PropertyAction { target: appDelegate; properties: "visuallyMinimized,visuallyMaximized" }
                        UbuntuNumberAnimation { target: appDelegate; properties: "requestedX,requestedY,requestedWidth,requestedHeight"; duration: priv.animationDuration }
                    },
                    Transition {
                        from: "spread"; to: "*"
//                        UbuntuNumberAnimation { target: appDelegate; properties: "x,y,height"; duration: priv.animationDuration }
//                        UbuntuNumberAnimation { target: decoratedWindow; properties: "width,height,itemScale,angle"; duration: priv.animationDuration }
//                        ScriptAction { script: if (appDelegate.focus) appDelegate.playFocusAnimation() }
                    },
                    Transition {
                        to: "minimized"
                        enabled: appDelegate.animationsEnabled
                        PropertyAction { target: appDelegate; property: "visuallyMaximized" }
                        SequentialAnimation {
                            ParallelAnimation {
                                UbuntuNumberAnimation { target: appDelegate; properties: "x,y,opacity,scale"; duration: priv.animationDuration }
                                UbuntuNumberAnimation { target: decoratedWindow; properties: "requestedWidth,requestedHeight"; duration: priv.animationDuration }
                            }
                            PropertyAction { target: appDelegate; property: "visuallyMinimized" }
                            ScriptAction {
                                script: {
                                    if (appDelegate.minimized) {
                                        appDelegate.focus = false;
                                        priv.focusNext();
                                    }
                                }
                            }
                        }
                    },
                    Transition {
                        to: "maximized,fullscreen"
                        enabled: appDelegate.animationsEnabled
                        SequentialAnimation {
                            PropertyAction { target: appDelegate; property: "visuallyMinimized" }
                            ParallelAnimation {
                                UbuntuNumberAnimation { target: appDelegate; properties: "requestedX,requestedY,opacity,scale,requestedWidth,requestedHeight"; duration: UbuntuAnimation.FastDuration }
                            }
                            PropertyAction { target: appDelegate; property: "visuallyMaximized" }
                        }
                    },
                    Transition {
                        to: "spread"
                        // DecoratedWindow wants the sceleToPreviewSize set before enabling scaleToPreview
                        PropertyAction { target: appDelegate; property: "z" }
                        PropertyAction { target: decoratedWindow; property: "scaleToPreviewSize" }
                        UbuntuNumberAnimation { target: appDelegate; properties: "x,y,height"; duration: priv.animationDuration }
                        UbuntuNumberAnimation { target: decoratedWindow; properties: "width,height,itemScale,angle,scaleToPreviewProgress"; duration: priv.animationDuration }
                    },
                    Transition {
                        from: "normal,staged"; to: "stagedWithSideStage"
                        UbuntuNumberAnimation { target: appDelegate; properties: "x,y"; duration: priv.animationDuration }
                        UbuntuNumberAnimation { target: appDelegate; properties: "requestedWidth,requestedHeight"; duration: priv.animationDuration }
                    },
                    Transition {
                        to: "windowedRightEdge"
                        ScriptAction {
                            script: {
                                windowedRightEdgeMaths.startX = appDelegate.requestedX
                                windowedRightEdgeMaths.startY = appDelegate.requestedY

                                if (index == 1) {
                                    print("should calculate overlap from", model.application.appId, "with", appRepeater.itemAt(0).application.appId)
                                    var thisRect = { x: appDelegate.windowedX, y: appDelegate.windowedY, width: appDelegate.requestedWidth, height: appDelegate.requestedHeight }
                                    print("thisRect:", thisRect.x, thisRect.y, thisRect.width, thisRect.height)
                                    var otherDelegate = appRepeater.itemAt(0);
                                    var otherRect = { x: otherDelegate.windowedX, y: otherDelegate.windowedY, width: otherDelegate.requestedWidth, height: otherDelegate.requestedHeight }
                                    print("otherRect:", otherRect.x, otherRect.y, otherRect.width, otherRect.height)
                                    var intersectionRect = MathUtils.intersectionRect(thisRect, otherRect)
                                    print("intersection is", intersectionRect.x, intersectionRect.y, intersectionRect.width, intersectionRect.height)
                                    var mappedInterSectionRect = appDelegate.mapFromItem(root, intersectionRect.x, intersectionRect.y)
                                    opacityEffect.maskX = mappedInterSectionRect.x
                                    opacityEffect.maskY = mappedInterSectionRect.y
                                    opacityEffect.maskWidth = intersectionRect.width
                                    opacityEffect.maskHeight = intersectionRect.height
                                }
                            }
                        }
                    },
                    Transition {
                        from: "stagedRightEdge"; to: "staged"
                        enabled: rightEdgeDragArea.cancelled // only transition back to state if the gesture was cancelled, in the other cases we play the focusAnimations.
                        SequentialAnimation {
                            ParallelAnimation {
                                UbuntuNumberAnimation { target: appDelegate; properties: "x,y,height,width,scale"; duration: priv.animationDuration }
                                UbuntuNumberAnimation { target: decoratedWindow; properties: "width,height,itemScale,angle,scaleToPreviewProgress"; duration: priv.animationDuration }
                            }
                            // We need to release scaleToPreviewSize at last
                            PropertyAction { target: decoratedWindow; property: "scaleToPreviewSize" }
                        }
                    }
                ]

                Binding {
                    target: PanelState
                    property: "buttonsAlwaysVisible"
                    value: appDelegate && appDelegate.maximized && touchControls.overlayShown
                }

                WindowResizeArea {
                    id: resizeArea
                    objectName: "windowResizeArea"

                    // workaround so that it chooses the correct resize borders when you drag from a corner ResizeGrip
                    anchors.margins: touchControls.overlayShown ? borderThickness/2 : -borderThickness

                    target: appDelegate
                    minWidth: units.gu(10)
                    minHeight: units.gu(10)
                    borderThickness: units.gu(2)
                    windowId: model.application.appId // FIXME: Change this to point to windowId once we have such a thing
                    screenWidth: appContainer.width
                    screenHeight: appContainer.height
                    leftMargin: root.leftMargin
                    enabled: false
                    visible: enabled

                    onPressed: {
                        print("***** focusing because of resize area press", model.application.appId)
                        appDelegate.focus = true;
                    }

                    Component.onCompleted: {
                        loadWindowState();
                    }

                    property bool saveStateOnDestruction: true
                    Component.onDestruction: {
                        if (saveStateOnDestruction) {
                            saveWindowState();
                        }
                    }
                }

                DecoratedWindow {
                    id: decoratedWindow
                    objectName: "decoratedWindow"
                    anchors.left: appDelegate.left
                    anchors.top: appDelegate.top
                    application: model.application
                    surface: model.surface
                    active: appDelegate.focus
                    focus: true
                    interactive: root.interactive
                    showDecoration: 1
                    maximizeButtonShown: (maximumWidth == 0 || maximumWidth >= appContainer.width) &&
                                         (maximumHeight == 0 || maximumHeight >= appContainer.height)
                    overlayShown: touchControls.overlayShown
                    width: implicitWidth
                    height: implicitHeight
                    highlightSize: windowInfoItem.iconMargin / 2

                    requestedWidth: appDelegate.requestedWidth
                    requestedHeight: appDelegate.requestedHeight

                    property int oldRequestedWidth: -1
                    property int oldRequestedHeight: -1

                    onRequestedWidthChanged: oldRequestedWidth = requestedWidth
                    onRequestedHeightChanged: oldRequestedHeight = requestedHeight

                    onCloseClicked: { appDelegate.close(); }
                    onMaximizeClicked: appDelegate.maximized || appDelegate.maximizedLeft || appDelegate.maximizedRight
                                       || appDelegate.maximizedHorizontally || appDelegate.maximizedVertically
                                       ? appDelegate.restoreFromMaximized() : appDelegate.maximize()
                    onMaximizeHorizontallyClicked: appDelegate.maximizedHorizontally ? appDelegate.restoreFromMaximized() : appDelegate.maximizeHorizontally()
                    onMaximizeVerticallyClicked: appDelegate.maximizedVertically ? appDelegate.restoreFromMaximized() : appDelegate.maximizeVertically()
                    onMinimizeClicked: appDelegate.minimize()
                    onDecorationPressed: {
                        print("focusing because of decoration press");
                        appDelegate.focus = true;
                    }

                    property real angle: 0
                    property real itemScale: 1
                    transform: [
                        Scale {
                            origin.x: 0
                            origin.y: decoratedWindow.implicitHeight / 2
                            xScale: decoratedWindow.itemScale
                            yScale: decoratedWindow.itemScale
                        },
                        Rotation {
                            origin { x: 0; y: (decoratedWindow.height / 2) }
                            axis { x: 0; y: 1; z: 0 }
                            angle: decoratedWindow.angle
                        }
                    ]
                }

                OpacityMask {
                    id: opacityEffect
                    anchors.fill: decoratedWindow
                }

                WindowControlsOverlay {
                    id: touchControls
                    anchors.fill: appDelegate
                    target: appDelegate
                    enabled: false
                    visible: enabled
                }

                WindowedFullscreenPolicy {
                    id: windowedFullscreenPolicy
                    active: root.mode == "windowed"
                    surface: model.surface
                }
                StagedFullscreenPolicy {
                    id: stagedFullscreenPolicy
                    active: root.mode == "staged" || root.mode == "stagedWithSideStage"
                    surface: model.surface
                }

                SpreadDelegateInputArea {
                    id: dragArea
                    objectName: "dragArea"
                    anchors.fill: decoratedWindow
                    enabled: false
                    closeable: model.application.appId !== "unity8-dash"

                    onClicked: {
                        spreadItem.highlightedIndex = index;
                        print("*****************setting highlighted index to:", index, appRepeater.itemAt(index))
                        if (distance == 0) {
                            priv.goneToSpread = false;
                        }
                    }
                    onClose: {
                        priv.closingIndex = index
                        model.surface.close()
                    }
                }

//                Rectangle { anchors.fill: parent; color: "blue"; opacity: .4 }

                WindowInfoItem {
                    id: windowInfoItem
                    objectName: "windowInfoItem"
                    anchors { left: parent.left; top: decoratedWindow.bottom; topMargin: units.gu(1) }
                    title: model.application.name
                    iconSource: model.application.icon
                    height: spreadItem.appInfoHeight
                    opacity: 0
                    z: 1
                    visible: opacity > 0
                }

                Image {
                    id: closeImage
                    anchors { left: parent.left; top: parent.top; leftMargin: -height / 2; topMargin: -height / 2 + spreadMaths.closeIconOffset }
                    source: "graphics/window-close.svg"
                    readonly property var mousePos: hoverMouseArea.mapToItem(appDelegate, hoverMouseArea.mouseX, hoverMouseArea.mouseY)
                    visible: model.application.appId !== "unity8-dash"
                             && index == spreadItem.highlightedIndex
                             && mousePos.y < (decoratedWindow.height / 3)
                             && mousePos.y > -units.gu(4)
                             && mousePos.x > -units.gu(4)
                             && mousePos.x < (decoratedWindow.width * 2 / 3)
                    height: units.gu(2)
                    width: height
                    sourceSize.width: width
                    sourceSize.height: height

                    MouseArea {
                        id: closeMouseArea
                        objectName: "closeMouseArea"
                        anchors.fill: closeImage
                        anchors.margins: -units.gu(2)
                        onClicked: {
                            priv.closingIndex = index;
                            model.surface.close();
                        }
                    }
                }
            }
        }
    }

    EdgeBarrier {
        id: edgeBarrier

        // NB: it does its own positioning according to the specified edge
        edge: Qt.RightEdge

        onPassed: priv.goneToSpread = true;

        material: Component {
            Item {
                Rectangle {
                    width: parent.height
                    height: parent.width
                    rotation: 90
                    anchors.centerIn: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(0.16,0.16,0.16,0.5)}
                        GradientStop { position: 1.0; color: Qt.rgba(0.16,0.16,0.16,0)}
                    }
                }
            }
        }
    }

    MouseArea {
        id: hoverMouseArea
        objectName: "hoverMouseArea"
        anchors.fill: appContainer
        propagateComposedEvents: true
        hoverEnabled: true
        enabled: false
        visible: enabled

        property int scrollAreaWidth: width / 3
        property bool progressiveScrollingEnabled: false

        onMouseXChanged: {
            mouse.accepted = false

            if (hoverMouseArea.pressed) {
                return;
            }

            // Find the hovered item and mark it active
            var mapped = mapToItem(appContainer, hoverMouseArea.mouseX, hoverMouseArea.mouseY)
            var itemUnder = appContainer.childAt(mapped.x, mapped.y)
            if (itemUnder) {
                mapped = mapToItem(itemUnder, hoverMouseArea.mouseX, hoverMouseArea.mouseY)
                var delegateChild = itemUnder.childAt(mapped.x, mapped.y)
                if (delegateChild && (delegateChild.objectName === "dragArea" || delegateChild.objectName === "windowInfoItem")) {
                    spreadItem.highlightedIndex = appRepeater.indexOf(itemUnder)
                }
            }

            if (floatingFlickable.contentWidth > floatingFlickable.width) {
                var margins = floatingFlickable.width * 0.05;

                if (!progressiveScrollingEnabled && mouseX < floatingFlickable.width - scrollAreaWidth) {
                    progressiveScrollingEnabled = true
                }

                // do we need to scroll?
                if (mouseX < scrollAreaWidth + margins) {
                    var progress = Math.min(1, (scrollAreaWidth + margins - mouseX) / (scrollAreaWidth - margins));
                    var contentX = (1 - progress) * (floatingFlickable.contentWidth - floatingFlickable.width)
                    floatingFlickable.contentX = Math.max(0, Math.min(floatingFlickable.contentX, contentX))
                }
                if (mouseX > floatingFlickable.width - scrollAreaWidth && progressiveScrollingEnabled) {
                    var progress = Math.min(1, (mouseX - (floatingFlickable.width - scrollAreaWidth)) / (scrollAreaWidth - margins))
                    var contentX = progress * (floatingFlickable.contentWidth - floatingFlickable.width)
                    floatingFlickable.contentX = Math.min(floatingFlickable.contentWidth - floatingFlickable.width, Math.max(floatingFlickable.contentX, contentX))
                }
            }
        }
        onPressed: mouse.accepted = false
    }

    FloatingFlickable {
        id: floatingFlickable
        anchors.fill: appContainer
        enabled: false
        contentWidth: spreadItem.spreadTotalWidth
    }

    PropertyAnimation {
        id: shortRightEdgeSwipeAnimation
        property: "x"
        to: 0
        duration: priv.animationDuration
    }

    SwipeArea {
        id: rightEdgeDragArea
        objectName: "rightEdgeDragArea"
        direction: Direction.Leftwards
        anchors { top: parent.top; right: parent.right; bottom: parent.bottom }
        width: root.dragAreaWidth

        property var gesturePoints: new Array()
        property bool cancelled: false

        property real progress: dragging ? -touchPosition.x / root.width : 0

        onTouchPositionChanged: {
            gesturePoints.push(touchPosition.x);
            if (gesturePoints.length > 10) {
                gesturePoints.splice(0, gesturePoints.length - 10)
            }
        }

        onDraggingChanged: {
            print("dda dragging changed", dragging)
            if (dragging) {
                // A potential edge-drag gesture has started. Start recording it
                gesturePoints = [];
                cancelled = false;
            } else {
                // Ok. The user released. Did he drag far enough to go to full spread?
                if (gesturePoints[gesturePoints.length - 1] < -spreadItem.rightEdgeBreakPoint * spreadItem.width ) {

                    // He dragged far enough, but if the last movement was a flick to the right again, he wants to cancel the spread again.
                    var oneWayFlickToRight = true;
                    var smallestX = gesturePoints[0]-1;
                    for (var i = 0; i < gesturePoints.length; i++) {
                        print("have point:", gesturePoints[i])
                        if (gesturePoints[i] <= smallestX) {
                            oneWayFlickToRight = false;
                            break;
                        }
                        smallestX = gesturePoints[i];
                    }

                    if (!oneWayFlickToRight) {
                        // Ok, the user made it, let's go to spread!
                        priv.goneToSpread = true;
                    } else {
                        cancelled = true;
                    }
                } else {
                    // Ok, the user didn't drag far enough to cross the breakPoint
                    // Find out if it was a one-way movement to the left, in which case we just switch directly to next app.
                    var oneWayFlick = true;
                    var smallestX = rightEdgeDragArea.width;
                    for (var i = 0; i < gesturePoints.length; i++) {
                        if (gesturePoints[i] >= smallestX) {
                            oneWayFlick = false;
                            break;
                        }
                        smallestX = gesturePoints[i];
                    }

                    if (appRepeater.count > 1 &&
                            (oneWayFlick && rightEdgeDragArea.distance > units.gu(2) || rightEdgeDragArea.distance > spreadItem.rightEdgeBreakPoint * spreadItem.width)) {
                        var nextStage = appRepeater.itemAt(priv.nextInStack).stage
                        for (var i = 0; i < appRepeater.count; i++) {
                            if (appRepeater.itemAt(i).stage == nextStage) {
                                appRepeater.itemAt(i).playHidingAnimation()
                                break;
                            }
                        }
                        print("playing focus animation 1")
                        appRepeater.itemAt(priv.nextInStack).playFocusAnimation()
                    } else {
                        cancelled = true;
                    }

                    gesturePoints = [];
                }
            }
        }
    }

    TabletSideStageTouchGesture {
        id: triGestureArea
        anchors.fill: parent
        enabled: false
        property Item appDelegate

        dragComponent: dragComponent
        dragComponentProperties: { "appDelegate": appDelegate }

        onPressed: {
            print("********* triGestureArea pressed!")
            function matchDelegate(obj) { return String(obj.objectName).indexOf("appDelegate") >= 0; }

            var delegateAtCenter = Functions.itemAt(appContainer, x, y, matchDelegate);
            print("dragging delegate", delegateAtCenter)
            if (!delegateAtCenter) return;

            appDelegate = delegateAtCenter;
        }

        onClicked: {
            if (sideStage.shown) {
               sideStage.hide();
            } else  {
               sideStage.show();
            }
        }

        onDragStarted: {
            // If we're dragging to the sidestage.
            if (!sideStage.shown) {
                sideStage.show();
            }
        }

        Component {
            id: dragComponent
            SurfaceContainer {
                property Item appDelegate

                surface: appDelegate ? appDelegate.surface : null

                consumesInput: false
                interactive: false
//                resizeSurface: false
                focus: false
                requestedWidth: appDelegate.requestedWidth
                requestedHeight: appDelegate.requestedHeight

                width: units.gu(40)
                height: units.gu(40)

                Drag.hotSpot.x: width/2
                Drag.hotSpot.y: height/2
                // only accept opposite stage.
                Drag.keys: {
                    if (!surface) return "Disabled";
                    if (appDelegate.isDash) return "Disabled";

                    if (appDelegate.stage === ApplicationInfo.MainStage) {
                        if (appDelegate.application.supportedOrientations
                                & (Qt.PortraitOrientation|Qt.InvertedPortraitOrientation)) {
                            return "MainStage";
                        }
                        return "Disabled";
                    }
                    return "SideStage";
                }
            }
        }
    }
}
