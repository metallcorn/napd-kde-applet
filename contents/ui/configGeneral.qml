import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page
    property alias cfg_displayMode: modeCombo.currentIndex

    Kirigami.FormLayout {
        QQC2.ComboBox {
            id: modeCombo
            Kirigami.FormData.label: i18n("Show in panel:")
            model: [
                i18n("Diagram with value"),
                i18n("Value only"),
                i18n("Diagram only")
            ]
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 18
            wrapMode: Text.WordWrap
            opacity: 0.7
            font: Kirigami.Theme.smallFont
            text: switch (modeCombo.currentIndex) {
                case 1: return i18n("A lightning bolt and the current power draw.")
                case 2: return i18n("Just the ring — managed vs. unmanaged power, no number.")
                default: return i18n("The ring with the current power draw in its centre.")
            }
        }
    }
}
