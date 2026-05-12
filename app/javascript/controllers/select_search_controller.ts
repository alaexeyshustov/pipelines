import { Controller } from "@hotwired/stimulus"
import TomSelect from "tom-select"
import type TomSelectType from "tom-select"

export default class SelectSearchController extends Controller {
  declare element: HTMLSelectElement
  private ts!: TomSelectType

  connect() {
    this.ts = new TomSelect(this.element, {
      maxOptions: null,
      plugins: ["clear_button"],
    })
  }

  disconnect() {
    this.ts?.destroy()
  }
}
