import { Controller } from "@hotwired/stimulus"

export default class DisclosureController extends Controller {
  static targets = ["content"]

  declare contentTargets: HTMLElement[]

  toggle() {
    this.contentTargets.forEach((el) => el.classList.toggle("hidden"))
  }
}
