import { Controller } from "@hotwired/stimulus"

export default class TabsController extends Controller {
  static targets = ["tab", "panel"]
  static values = { index: { type: Number, default: 0 } }

  declare tabTargets: HTMLElement[]
  declare panelTargets: HTMLElement[]
  declare indexValue: number

  connect() {
    this.showTab()
  }

  show(event: Event) {
    this.indexValue = this.tabTargets.indexOf(event.currentTarget as HTMLElement)
  }

  indexValueChanged() {
    this.showTab()
  }

  private showTab() {
    this.panelTargets.forEach((panel, i) => {
      panel.hidden = i !== this.indexValue
    })
    this.tabTargets.forEach((tab, i) => {
      const active = i === this.indexValue
      tab.setAttribute("aria-selected", String(active))
      tab.classList.toggle("border-indigo-600", active)
      tab.classList.toggle("text-indigo-600", active)
      tab.classList.toggle("border-transparent", !active)
      tab.classList.toggle("text-gray-500", !active)
    })
  }
}
