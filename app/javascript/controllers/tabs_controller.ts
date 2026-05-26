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

  keydown(event: KeyboardEvent) {
    const tabs = this.tabTargets
    let i = this.indexValue
    if (event.key === "ArrowRight") i = (i + 1) % tabs.length
    else if (event.key === "ArrowLeft") i = (i - 1 + tabs.length) % tabs.length
    else if (event.key === "Home") i = 0
    else if (event.key === "End") i = tabs.length - 1
    else return
    event.preventDefault()
    this.indexValue = i
    ;(tabs[i] as HTMLElement).focus()
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
      tab.setAttribute("tabindex", active ? "0" : "-1")
      tab.classList.toggle("border-indigo-600", active)
      tab.classList.toggle("text-indigo-600", active)
      tab.classList.toggle("border-transparent", !active)
      tab.classList.toggle("text-gray-500", !active)
    })
  }
}
