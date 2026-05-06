import { Controller } from "@hotwired/stimulus"

export default class AccordionController extends Controller {
  static targets = ["details"]

  declare detailsTargets: HTMLDetailsElement[]

  toggle(event: Event) {
    const opened = event.target as HTMLDetailsElement
    this.detailsTargets.forEach((details) => {
      if (details !== opened) details.removeAttribute("open")
    })
  }

  connect() {
    this.detailsTargets.forEach((details) => {
      details.addEventListener("toggle", this.toggle.bind(this))
    })
  }

  disconnect() {
    this.detailsTargets.forEach((details) => {
      details.removeEventListener("toggle", this.toggle.bind(this))
    })
  }
}
