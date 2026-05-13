import { Controller } from "@hotwired/stimulus"

// Reloads the prompt-version <select> when the agent selection changes.
export default class AgentSelectController extends Controller {
  static values = { versionsUrl: String }

  declare versionsUrlValue: string

  async loadVersions(event: Event) {
    const agentName = (event.target as HTMLSelectElement).value
    const promptSelect = document.getElementById("wizard_prompt_id") as HTMLSelectElement | null
    if (!promptSelect) return

    if (!agentName) {
      promptSelect.innerHTML = '<option value="">— latest —</option>'
      return
    }

    const url = new URL(this.versionsUrlValue, window.location.origin)
    url.searchParams.set("agent_name", agentName)

    const response = await fetch(url.toString(), {
      headers: { Accept: "application/json" },
    })
    if (!response.ok) return

    const versions: { id: number; version: number; active: boolean }[] = await response.json()
    promptSelect.innerHTML = '<option value="">— latest —</option>'
    versions.forEach(({ id, version, active }) => {
      const opt = document.createElement("option")
      opt.value = String(id)
      opt.textContent = `v${version}${active ? " ✓" : ""}`
      promptSelect.appendChild(opt)
    })
  }
}
