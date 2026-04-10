import { Controller } from "@hotwired/stimulus"

interface BatchSubmitParams {
  batchAction: string
  confirmMsg?: string
  requireSelection?: boolean | string
}

interface StimulusActionEvent extends Event {
  params: BatchSubmitParams
}

export default class BatchController extends Controller {
  static targets = ["checkbox", "selectAllBtn", "gistModalIds"]

  declare readonly checkboxTargets: HTMLInputElement[]
  declare readonly selectAllBtnTarget: HTMLElement
  declare readonly gistModalIdsTarget: HTMLElement

  toggleSelectAll(): void {
    const allChecked = this.checkboxTargets.every((cb) => cb.checked)
    this.checkboxTargets.forEach((cb) => { cb.checked = !allChecked })
    this.selectAllBtnTarget.textContent = allChecked ? "Select all" : "Deselect all"
  }

  batchSubmit(event: StimulusActionEvent): void {
    event.preventDefault()

    const { batchAction, confirmMsg } = event.params
    const requireSelection =
      event.params.requireSelection !== false && event.params.requireSelection !== "false"
    const checked = this.checkboxTargets.filter((cb) => cb.checked)

    if (requireSelection && checked.length === 0) {
      alert("Please select at least one record.")
      return
    }
    if (confirmMsg && !confirm(confirmMsg)) return

    const button = event.target as HTMLElement
    const form = button.closest("form")!

    const actionInput = document.createElement("input")
    actionInput.type = "hidden"
    actionInput.name = "batch_action"
    actionInput.value = batchAction
    form.appendChild(actionInput)

    checked.forEach((cb) => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "ids[]"
      input.value = cb.value
      form.appendChild(input)
    })

    form.submit()
  }

  prepareGistIds(): void {
    this.gistModalIdsTarget.innerHTML = ""
    this.checkboxTargets.filter((cb) => cb.checked).forEach((cb) => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "ids[]"
      input.value = cb.value
      this.gistModalIdsTarget.appendChild(input)
    })
  }
}
