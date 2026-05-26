import { Controller } from "@hotwired/stimulus"

export default class ResyncController extends Controller {
  static targets = ["dialog", "status"]

  declare dialogTarget: HTMLDialogElement
  declare statusTarget: HTMLElement

  submit(): void {
    this.dialogTarget.close()
    this.statusTarget.innerHTML = `
      <div class="flex items-center gap-1.5 text-gray-500">
        <svg class="animate-spin h-3.5 w-3.5 flex-shrink-0" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.368 3 6.831l3-2.54z"></path>
        </svg>
        Resyncing…
      </div>
    `
  }
}
