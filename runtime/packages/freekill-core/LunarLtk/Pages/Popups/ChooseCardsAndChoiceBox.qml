// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

import Fk
import Fk.Components.Common

import LunarLtk
import LunarLtk.Components
import LunarLtk.Models.Popups

GraphicsBox {
  id: root
  required property ChooseCardsAndChoiceModel dataModel

  title.text: dataModel.promptText || Lua.tr("$ChooseCard")
  width: 40 + Math.min(8.5, Math.max(4, dataModel.cards.length)) * 100
  height: 320

  Component {
    id: cardDelegate
    CardItem {
      required property var modelData
      dataModel: Ltk.createCardModel(modelData)
      autoBack: false
      showDetail: true
      selectable: !root.dataModel.disabledCards.includes(modelData)
      onSelectedChanged: {
        const selectedCards = root.dataModel.result.cards;
        if (!selectedCards) return;
        const cardId = dataModel.cardId;
        if (selected) {
          origY = origY - 20;
          if (!selectedCards.includes(cardId)) selectedCards.push(cardId);
        } else {
          origY = origY + 20;
          const idx = selectedCards.indexOf(cardId);
          if (idx >= 0) selectedCards.splice(idx, 1);
        }
        origX = x;
        goBack(true);
        updateCardSelectable();
      }
    }
  }

  ColumnLayout {
    id: mainLayout
    anchors.top: root.title.bottom
    anchors.topMargin: 12
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 12
    anchors.leftMargin: 15
    anchors.rightMargin: 15
    spacing: 10

    Rectangle {
      id: cardbox
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.minimumHeight: 200
      color: "#1D1E19"
      radius: 10
      clip: true

      Flickable {
        id: flickableContainer
        anchors.fill: parent
        anchors.margins: 6
        ScrollBar.horizontal: ScrollBar {}
        flickableDirection: Flickable.HorizontalFlick
        contentWidth: Math.max(cardsList.width, width)
        contentHeight: Math.max(cardsList.height + 15, height)
        clip: true

        Row {
          id: cardsList
          x: Math.max(0, (flickableContainer.width - width) / 2)
          y: 25
          spacing: 5
          Repeater {
            id: to_select
            model: root.dataModel.cards
            delegate: cardDelegate
          }
        }
      }
    }

    Row {
      id: buttonRow
      Layout.alignment: Qt.AlignHCenter
      Layout.preferredHeight: implicitHeight
      spacing: 8

      Repeater {
        id: choicesRepeater
        model: root.dataModel.choices

        MetroButton {
          text: Ltk.processPrompt(modelData)
          enabled: {
            const cards = root.dataModel.result.cards;
            return root.dataModel.choiceEnabled(cards, modelData, index);
          }
          onClicked: root.dataModel.toggleChoose(modelData);
        }
      }

      Repeater {
        model: root.dataModel.cancelChoices
        MetroButton {
          text: Ltk.processPrompt(modelData)
          enabled: true
          onClicked: {
            root.dataModel.result.cards = [];
            root.dataModel.toggleChoose(modelData);
          }
        }
      }
    }
  }

  function updateCardSelectable() {
    const selectedCards = root.dataModel.result.cards;
    const maxNum = root.dataModel.maxNum;
    for (let i = 0; i < choicesRepeater.count; i++) {
      const btn = choicesRepeater.itemAt(i);
      if (btn) {
        const choiceData = root.dataModel.choices[i];
        btn.enabled = root.dataModel.choiceEnabled(selectedCards, choiceData, i);
      }
    }
    if (selectedCards.length <= maxNum) return;

    for (let i = 0; i < to_select.count; i++) {
      const item = to_select.itemAt(i);
      if (item?.modelData?.cardId === selectedCards[0]) {
        item.selected = false;
        break;
      }
    }
  }
}