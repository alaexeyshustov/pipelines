import { Controller } from "@hotwired/stimulus"

export default class SchemaBuilderController extends Controller {
  static targets = ["json", "schemaData", "rawEditor", "builderFrame", "rawToggleBtn"]

  declare jsonTarget: HTMLInputElement
  declare schemaDataTarget: HTMLInputElement
  declare rawEditorTarget: HTMLTextAreaElement
  declare builderFrameTarget: HTMLElement
  declare rawToggleBtnTarget: HTMLButtonElement
  declare hasRawEditorTarget: boolean
  declare hasBuilderFrameTarget: boolean
  declare hasRawToggleBtnTarget: boolean

  private showingRaw = false

  // Stimulus calls this when schemaData target connects (including after Turbo Frame updates)
  schemaDataTargetConnected(element: HTMLInputElement) {
    this.jsonTarget.value = element.value
    if (this.hasRawEditorTarget) {
      this.rawEditorTarget.value = this.prettyJson(element.value)
    }
  }

  toggleRaw() {
    this.showingRaw = !this.showingRaw
    if (this.hasBuilderFrameTarget) {
      this.builderFrameTarget.style.display = this.showingRaw ? "none" : ""
    }
    if (this.hasRawEditorTarget) {
      this.rawEditorTarget.style.display = this.showingRaw ? "" : "none"
      if (this.showingRaw) {
        this.rawEditorTarget.value = this.prettyJson(this.jsonTarget.value)
      }
    }
    if (this.hasRawToggleBtnTarget) {
      this.rawToggleBtnTarget.textContent = this.showingRaw ? "← Builder" : "Raw JSON"
    }
  }

  applyRaw() {
    const json = this.rawEditorTarget.value.trim()
    if (!json) return

    const form = this.rawEditorTarget.closest("form") as HTMLFormElement | null
    if (form) {
      const input = form.querySelector("input[name='json']") as HTMLInputElement | null
      if (input) input.value = json
      form.requestSubmit()
    }
    this.toggleRaw()
  }

  private prettyJson(raw: string): string {
    try {
      return JSON.stringify(JSON.parse(raw), null, 2)
    } catch {
      return raw
    }
  }
}
