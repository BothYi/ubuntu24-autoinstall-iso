import * as Main from "resource:///org/gnome/shell/ui/main.js";

export default class HidePanelExtension {
    enable() {
        this._panel = Main.panel;
        this._panel.hide();
    }
    disable() {
        this._panel.show();
    }
}
