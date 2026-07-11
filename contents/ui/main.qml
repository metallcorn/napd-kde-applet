pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    property var snap: ({})
    readonly property var meta: snap.meta ?? ({})
    readonly property var apps: snap.apps ?? []
    readonly property bool onBattery: meta.source === "battery"
    readonly property bool alive: meta.mode !== undefined
    readonly property bool recording: {
        for (let i = 0; i < apps.length; i++)
            if (apps[i].capture && apps[i].capture.length) return true
        return false
    }
    readonly property int cappedCount: {
        let n = 0
        for (let i = 0; i < apps.length; i++)
            if (apps[i].status === "throttled") n++
        return n
    }
    // only apps actually using CPU — idle ones are noise here
    property var appRows: aggApps().filter(r => r.cpu >= 0.5)

    Plasmoid.icon: "speedometer"
    // relevant only when napd is actually managing (on battery) — lets the
    // tray's "Show when relevant" hide it on charger and show it on battery
    Plasmoid.status: (alive && onBattery)
        ? PlasmaCore.Types.ActiveStatus
        : PlasmaCore.Types.PassiveStatus

    // ---------- data ----------
    property var daily: []          // per-app energy today (from DailyUsage)
    property bool showDaily: false  // "Today's battery use" expanded?
    P5Support.DataSource {
        id: ds
        engine: "executable"
        readonly property string statusCmd: "qdbus6 ai.palabra.NapD /ai/palabra/NapD ai.palabra.NapD.Status"
        readonly property string dailyCmd: "qdbus6 ai.palabra.NapD /ai/palabra/NapD ai.palabra.NapD.DailyUsage"
        onNewData: function (src, data) {
            disconnectSource(src)
            if (data["exit code"] !== 0 || !data["stdout"]) return
            try {
                if (src === statusCmd) root.snap = JSON.parse(data["stdout"])
                else if (src === dailyCmd) root.daily = JSON.parse(data["stdout"]).apps
            } catch (e) {}
        }
    }
    // drive the compact donut + popup; 3s is plenty live and ~⅓ fewer spawns than 2s
    Timer { interval: 3000; running: true; repeat: true; triggeredOnStart: true; onTriggered: ds.connectSource(ds.statusCmd) }
    // daily breakdown only matters while the popup is open — don't poll when collapsed
    Timer { interval: 20000; running: root.expanded; repeat: true; triggeredOnStart: true; onTriggered: ds.connectSource(ds.dailyCmd) }

    toolTipMainText: "napd"
    toolTipSubText: {
        if (!alive) return i18n("Starting…")
        let s = onBattery ? i18n("On battery") : i18n("On charger — full speed")
        if (onBattery && cappedCount > 0) s += " · " + i18np("%1 app asleep", "%1 apps asleep", cappedCount)
        if (recording) s += " · " + i18n("recording")
        return s
    }

    // ---------- helpers ----------
    function shortName(id) { const p = id.split("."); return p.length > 2 ? p[p.length - 1] : id }
    function aggApps() {
        const rank = { "throttled": 4, "would-throttle": 3, "watching": 2, "focused": 1, "idle": 0 }
        let m = {}, order = []
        for (let i = 0; i < apps.length; i++) {
            const a = apps[i]; let g = m[a.app]
            if (!g) { g = { app: a.app, cpu: 0, focused: false, status: "idle", reason: "", capture: "", anom: false, usual: null }; m[a.app] = g; order.push(a.app) }
            g.cpu += a.cpu_pct || 0
            if (a.state === "focused") g.focused = true
            if ((rank[a.status] || 0) > (rank[g.status] || 0)) { g.status = a.status; g.reason = a.reason }
            if (a.capture && g.capture.indexOf(a.capture) < 0) g.capture = a.capture
            if (a.anom) g.anom = true
            if (a.usual != null) g.usual = a.usual
        }
        let arr = []
        for (let k = 0; k < order.length; k++) arr.push(m[order[k]])
        arr.sort((x, y) => y.cpu - x.cpu)
        return arr
    }
    function statusText(r) {
        if (r.anom) return r.usual != null ? i18n("⚠ usual ~%1%", Math.round(r.usual)) : i18n("⚠ above usual")
        if (r.focused) return i18n("Focused")
        if (r.status === "throttled") return i18n("Capped")
        if (r.status === "would-throttle") return i18n("Would cap")
        if (r.capture) return i18n("Protected")
        if (r.status === "watching") {
            const why = r.reason.indexOf("(") >= 0 ? r.reason.split("(")[1].replace(")", "") : "protected"
            return i18n("Protected · %1", why)
        }
        return i18n("Idle")
    }
    function statusColor(r) {
        if (r.anom) return Kirigami.Theme.neutralTextColor
        if (r.focused) return Kirigami.Theme.highlightColor
        if (r.status === "throttled") return Kirigami.Theme.positiveTextColor
        if (r.capture) return Kirigami.Theme.neutralTextColor
        return Kirigami.Theme.disabledTextColor
    }
    function modeText() {
        if (!alive) return ""
        if (meta.mode !== "enforce") return i18n("Observing")
        return onBattery ? i18n("Enforcing") : i18n("Paused")
    }

    // ---------- compact: 0 = donut+value · 1 = value only · 2 = donut only ----------
    compactRepresentation: Item {
        id: comp
        clip: true   // never paint over neighbouring tray icons
        readonly property int mode: Plasmoid.configuration.displayMode
        readonly property bool donutMode: mode !== 1
        readonly property bool valueOnly: mode === 1
        readonly property bool drawNumber: mode === 0
        readonly property string wattsText: {
            if (root.onBattery && root.meta.total_watts != null) return i18n("%1 W", Math.round(root.meta.total_watts))
            if (root.meta.amdgpu_watts != null) return i18n("%1 W", Math.round(root.meta.amdgpu_watts))
            return "—"
        }

        readonly property string valueNumber: {
            if (root.onBattery && root.meta.total_watts != null) return Math.round(root.meta.total_watts).toString()
            if (root.meta.amdgpu_watts != null) return Math.round(root.meta.amdgpu_watts).toString()
            return "—"
        }

        // square in every mode → fits a system-tray cell, never overlaps neighbours
        Layout.minimumWidth: Kirigami.Units.iconSizes.small
        Layout.minimumHeight: Kirigami.Units.iconSizes.small
        Layout.preferredWidth: height

        // ---- donut (modes 0 & 2) ----
        Canvas {
            id: donut
            anchors.fill: parent
            visible: comp.donutMode
            antialiasing: true
            property color txt: Kirigami.Theme.textColor
            property color acc: Kirigami.Theme.highlightColor
            property color rec: Kirigami.Theme.negativeTextColor
            property bool batt: root.onBattery
            property real total: root.meta.total_watts ?? -1
            property real managed: root.meta.addressable_watts ?? 0
            property real amd: root.meta.amdgpu_watts ?? -1
            property bool rng: root.recording
            property bool drawNum: comp.drawNumber
            onTxtChanged: requestPaint(); onAccChanged: requestPaint()
            onBattChanged: requestPaint(); onTotalChanged: requestPaint()
            onManagedChanged: requestPaint(); onRngChanged: requestPaint()
            onDrawNumChanged: requestPaint(); onVisibleChanged: if (visible) requestPaint()
            function at(d) { return (d - 90) * Math.PI / 180 }
            onPaint: {
                const ctx = getContext("2d"); ctx.reset()
                const cx = width / 2, cy = height / 2
                const lw = Math.max(2, Math.round(Math.min(width, height) * 0.11))
                const r = Math.min(width, height) / 2 - lw / 2 - 1
                const innerR = r - lw / 2
                ctx.lineWidth = lw
                const hasWatts = batt && total > 0
                const mg = hasWatts ? Math.max(0, Math.min(1, managed / total)) : 0
                if (hasWatts) {
                    ctx.strokeStyle = Qt.rgba(txt.r, txt.g, txt.b, 0.30)
                    ctx.beginPath(); ctx.arc(cx, cy, r, at(360 * mg), at(360)); ctx.stroke()
                    if (mg > 0) {
                        ctx.strokeStyle = acc
                        ctx.beginPath(); ctx.arc(cx, cy, r, at(0), at(360 * mg)); ctx.stroke()
                    }
                } else {
                    ctx.strokeStyle = Qt.rgba(txt.r, txt.g, txt.b, 0.22)
                    ctx.beginPath(); ctx.arc(cx, cy, r, 0, 2 * Math.PI); ctx.stroke()
                }
                if (drawNum) {
                    let label = hasWatts ? Math.round(total).toString()
                              : (amd > 0 ? Math.round(amd).toString() : "")
                    if (label.length) {
                        ctx.fillStyle = hasWatts ? txt : Qt.rgba(txt.r, txt.g, txt.b, 0.65)
                        ctx.textAlign = "center"; ctx.textBaseline = "middle"
                        let fs = innerR * (label.length >= 2 ? 1.25 : 1.55)
                        ctx.font = "700 " + Math.round(fs) + "px sans-serif"
                        ctx.fillText(label, cx, cy + 1)
                    }
                }
                if (rng) {
                    const dr = Math.max(2, lw * 0.5)
                    ctx.fillStyle = rec
                    ctx.beginPath(); ctx.arc(width - dr, dr, dr, 0, 2 * Math.PI); ctx.fill()
                }
            }
            Connections { target: root; function onSnapChanged() { donut.requestPaint() } }
        }

        // ---- value only (mode 1): bolt over the number — fits the square cell ----
        ColumnLayout {
            id: valueCol
            visible: comp.valueOnly
            anchors.centerIn: parent
            spacing: 0
            Canvas {
                id: bolt
                Layout.alignment: Qt.AlignHCenter
                implicitHeight: Math.round(comp.height * 0.38)
                implicitWidth: Math.round(implicitHeight * 0.62)
                property color c: root.onBattery ? Kirigami.Theme.highlightColor : Kirigami.Theme.disabledTextColor
                onCChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d"); ctx.reset()
                    const w = width, h = height
                    ctx.fillStyle = c
                    ctx.beginPath()
                    ctx.moveTo(w * 0.58, 0); ctx.lineTo(w * 0.10, h * 0.58); ctx.lineTo(w * 0.45, h * 0.58)
                    ctx.lineTo(w * 0.40, h); ctx.lineTo(w * 0.92, h * 0.36); ctx.lineTo(w * 0.55, h * 0.36)
                    ctx.closePath(); ctx.fill()
                }
            }
            PlasmaComponents.Label {
                Layout.alignment: Qt.AlignHCenter
                text: comp.valueNumber
                horizontalAlignment: Text.AlignHCenter
                font.bold: true
                font.pixelSize: Math.round(comp.height * 0.46)
            }
        }
    }

    // ---------- full: native popup ----------
    fullRepresentation: PlasmaExtras.Representation {
        collapseMarginsHint: true
        Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        Layout.minimumHeight: Kirigami.Units.gridUnit * 16
        Layout.preferredWidth: Kirigami.Units.gridUnit * 19
        Layout.preferredHeight: Kirigami.Units.gridUnit * 22

        header: PlasmaExtras.PlasmoidHeading {
            contentItem: RowLayout {
                spacing: Kirigami.Units.smallSpacing
                Kirigami.Heading { level: 1; text: "napd"; Layout.fillWidth: true; elide: Text.ElideRight }
                PlasmaComponents.Label {
                    text: root.modeText()
                    color: (root.meta.mode === "enforce" && root.onBattery) ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.disabledTextColor
                }
            }
        }

        PlasmaComponents.ScrollView {
            id: scroll
            anchors.fill: parent
            contentWidth: availableWidth

            ColumnLayout {
                width: scroll.availableWidth
                spacing: Kirigami.Units.largeSpacing

                // ---- power ----
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.gridUnit
                    Layout.rightMargin: Kirigami.Units.gridUnit
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Heading {
                        level: 1
                        text: root.meta.total_watts != null ? i18n("%1 W", root.meta.total_watts.toFixed(1)) : i18n("On charger")
                    }
                    PlasmaComponents.ProgressBar {
                        Layout.fillWidth: true
                        visible: root.meta.total_watts != null
                        from: 0
                        to: Math.max(0.001, root.meta.total_watts ?? 1)
                        value: root.meta.addressable_watts ?? 0
                    }
                    PlasmaComponents.Label {
                        visible: root.meta.total_watts != null
                        text: i18n("Apps napd manages: %1 W", (root.meta.addressable_watts ?? 0).toFixed(1))
                        font: Kirigami.Theme.smallFont
                        color: Kirigami.Theme.disabledTextColor
                    }
                }

                Kirigami.Separator { Layout.fillWidth: true }

                // ---- apps using CPU ----
                Kirigami.Heading {
                    level: 3; text: i18n("Using CPU"); opacity: 0.8
                    Layout.leftMargin: Kirigami.Units.gridUnit
                }
                Repeater {
                    model: root.appRows
                    delegate: PlasmaComponents.ItemDelegate {
                        required property var modelData
                        Layout.fillWidth: true
                        hoverEnabled: false
                        down: false
                        contentItem: RowLayout {
                            spacing: Kirigami.Units.smallSpacing
                            Rectangle {
                                implicitWidth: Kirigami.Units.smallSpacing * 1.5
                                implicitHeight: implicitWidth; radius: implicitWidth / 2
                                color: root.statusColor(modelData)
                            }
                            PlasmaComponents.Label {
                                text: root.shortName(modelData.app); Layout.fillWidth: true; elide: Text.ElideRight
                            }
                            PlasmaComponents.Label {
                                text: i18n("%1%", modelData.cpu.toFixed(0)); color: Kirigami.Theme.disabledTextColor
                            }
                            PlasmaComponents.Label {
                                text: root.statusText(modelData); color: root.statusColor(modelData)
                                font: Kirigami.Theme.smallFont
                            }
                        }
                    }
                }
                PlasmaComponents.Label {
                    visible: root.appRows.length === 0
                    Layout.leftMargin: Kirigami.Units.gridUnit
                    Layout.bottomMargin: Kirigami.Units.smallSpacing
                    text: i18n("Nothing's busy")
                    color: Kirigami.Theme.disabledTextColor; font: Kirigami.Theme.smallFont
                }

                // ---- today's battery use (per-app energy, expandable) ----
                Kirigami.Separator { Layout.fillWidth: true; visible: root.daily.length > 0 }
                PlasmaComponents.ItemDelegate {
                    Layout.fillWidth: true
                    visible: root.daily.length > 0
                    onClicked: root.showDaily = !root.showDaily
                    contentItem: RowLayout {
                        spacing: Kirigami.Units.smallSpacing
                        Kirigami.Icon {
                            implicitWidth: Kirigami.Units.iconSizes.small; implicitHeight: width
                            source: root.showDaily ? "go-down-symbolic" : "go-next-symbolic"
                        }
                        Kirigami.Heading { level: 3; text: i18n("Today's battery use"); opacity: 0.8; Layout.fillWidth: true }
                    }
                }
                Repeater {
                    model: root.showDaily ? root.daily : []
                    delegate: PlasmaComponents.ItemDelegate {
                        required property var modelData
                        Layout.fillWidth: true
                        hoverEnabled: false
                        down: false
                        contentItem: RowLayout {
                            spacing: Kirigami.Units.smallSpacing
                            PlasmaComponents.Label {
                                text: root.shortName(modelData.app)
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 6
                                elide: Text.ElideRight
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: Kirigami.Units.gridUnit * 0.5
                                radius: height / 2
                                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
                                Rectangle {
                                    height: parent.height; radius: height / 2
                                    width: parent.width * Math.min(1, modelData.wh / Math.max(0.0001, root.daily[0].wh))
                                    color: Kirigami.Theme.highlightColor
                                }
                            }
                            PlasmaComponents.Label {
                                text: modelData.wh >= 0.05 ? i18n("%1 Wh", modelData.wh.toFixed(2))
                                                           : i18n("%1 mWh", Math.round(modelData.wh * 1000))
                                color: Kirigami.Theme.disabledTextColor; font: Kirigami.Theme.smallFont
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 3.5
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true; Layout.minimumHeight: Kirigami.Units.smallSpacing }
            }
        }
    }
}
