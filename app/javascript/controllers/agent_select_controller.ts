import { Controller } from "@hotwired/stimulus"

// Manages agent/prompt selection on the experiment wizard step 1 form.
// Handles version loading, snapshotting from agent settings, and inline prompt editing.
export default class AgentSelectController extends Controller {
  static values = {
    versionsUrl:      String,
    snapshotUrl:      String,
    currentAgentName: String,
    forkPromptUrl:    String,
    promptContentUrl: String,
  }
  static targets = [
    "promptSelect",
    "snapshotButton",
    "editToggle",
    "editPanel",
    "systemPromptField",
    "userPromptField",
    "outputSchemaField",
    "submitButton",
  ]

  declare versionsUrlValue:      string
  declare snapshotUrlValue:      string
  declare currentAgentNameValue: string
  declare forkPromptUrlValue:    string
  declare promptContentUrlValue: string

  declare promptSelectTarget:     HTMLSelectElement
  declare snapshotButtonTarget:   HTMLButtonElement
  declare editToggleTarget:       HTMLButtonElement
  declare editPanelTarget:        HTMLElement
  declare systemPromptFieldTarget: HTMLTextAreaElement
  declare userPromptFieldTarget:   HTMLTextAreaElement
  declare outputSchemaFieldTarget: HTMLTextAreaElement
  declare submitButtonTarget:     HTMLButtonElement

  declare hasEditToggleTarget:        boolean
  declare hasEditPanelTarget:         boolean
  declare hasSystemPromptFieldTarget: boolean
  declare hasSubmitButtonTarget:      boolean

  private originalSystemPrompt = ""
  private originalUserPrompt   = ""
  private contentLoaded        = false

  connect() {
    this.element.addEventListener("submit", (e: Event) => this.handleSubmit(e))
  }

  async loadVersions(event: Event) {
    const agentName = (event.target as HTMLSelectElement).value
    this.currentAgentNameValue = agentName

    this.promptSelectTarget.innerHTML = '<option value="">— latest —</option>'
    this.snapshotButtonTarget.disabled = !agentName
    this.snapshotButtonTarget.textContent = "+ Create new version from current agent settings"

    if (this.hasEditToggleTarget) {
      this.editToggleTarget.disabled = true
    }
    this.closeEditPanel()
    this.contentLoaded = false

    if (!agentName) return

    const url = new URL(this.versionsUrlValue, window.location.origin)
    url.searchParams.set("agent_name", agentName)

    const response = await fetch(url.toString(), {
      headers: { Accept: "application/json" },
    })
    if (!response.ok) return

    const versions: { id: number; version: number; active: boolean }[] = await response.json()
    versions.forEach(({ id, version, active }) => {
      const opt = document.createElement("option")
      opt.value = String(id)
      opt.textContent = `v${version}${active ? " ✓" : ""}`
      this.promptSelectTarget.appendChild(opt)
    })
  }

  promptVersionChanged(event: Event) {
    const promptId = (event.target as HTMLSelectElement).value
    if (this.hasEditToggleTarget) {
      this.editToggleTarget.disabled = !promptId
    }
    this.closeEditPanel()
    this.contentLoaded = false
  }

  async toggleEdit(event: Event) {
    event.preventDefault()
    if (this.isPanelOpen()) {
      this.closeEditPanel()
    } else {
      await this.openEditPanel()
    }
  }

  async snapshot(event: Event) {
    event.preventDefault()
    const agentName = this.currentAgentNameValue
    if (!agentName) return

    const button = this.snapshotButtonTarget
    const originalText = button.textContent ?? ""
    button.disabled = true
    button.textContent = "Creating…"

    const token = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? ""

    const response = await fetch(this.snapshotUrlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": token,
      },
      body: JSON.stringify({ agent_name: agentName }),
    })

    if (response.ok) {
      const { id, version } = (await response.json()) as { id: number; version: number }
      const opt = document.createElement("option")
      opt.value = String(id)
      opt.textContent = `v${version} (from agent settings)`
      this.promptSelectTarget.appendChild(opt)
      this.promptSelectTarget.value = String(id)
      button.textContent = `✓ Created v${version}`
      if (this.hasEditToggleTarget) {
        this.editToggleTarget.disabled = false
      }
    } else {
      button.textContent = originalText
      button.disabled = false
    }
  }

  // --- private-ish helpers ---

  private async openEditPanel() {
    const promptId = this.promptSelectTarget.value
    if (!promptId || !this.hasEditPanelTarget) return

    this.editPanelTarget.classList.remove("hidden")
    this.editToggleTarget.textContent = "✕ Close editor"

    if (!this.contentLoaded) {
      await this.loadPromptContent(promptId)
    }
  }

  private closeEditPanel() {
    if (!this.hasEditPanelTarget) return
    this.editPanelTarget.classList.add("hidden")
    if (this.hasEditToggleTarget) {
      this.editToggleTarget.textContent = "✏ Edit prompt"
    }
  }

  private isPanelOpen(): boolean {
    return this.hasEditPanelTarget && !this.editPanelTarget.classList.contains("hidden")
  }

  private async loadPromptContent(promptId: string) {
    const url = new URL(this.promptContentUrlValue, window.location.origin)
    url.searchParams.set("prompt_id", promptId)

    const response = await fetch(url.toString(), { headers: { Accept: "application/json" } })
    if (!response.ok) return

    const data = (await response.json()) as {
      system_prompt: string | null
      user_prompt: string | null
      output_schema: object | null
    }

    this.systemPromptFieldTarget.value  = data.system_prompt ?? ""
    this.userPromptFieldTarget.value    = data.user_prompt   ?? ""
    this.outputSchemaFieldTarget.value  = data.output_schema ? JSON.stringify(data.output_schema, null, 2) : ""

    this.originalSystemPrompt = this.systemPromptFieldTarget.value
    this.originalUserPrompt   = this.userPromptFieldTarget.value
    this.contentLoaded        = true
  }

  private isContentDirty(): boolean {
    if (!this.contentLoaded) return false
    return (
      this.systemPromptFieldTarget.value !== this.originalSystemPrompt ||
      this.userPromptFieldTarget.value   !== this.originalUserPrompt
    )
  }

  private async handleSubmit(event: Event) {
    if (!this.isPanelOpen() || !this.isContentDirty()) return
    event.preventDefault()
    await this.forkAndSubmit()
  }

  private async forkAndSubmit() {
    const submitButton = this.hasSubmitButtonTarget ? this.submitButtonTarget : null
    const originalText = submitButton?.textContent ?? ""
    if (submitButton) {
      submitButton.disabled = true
      submitButton.textContent = "Saving…"
    }

    const token = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? ""
    const promptId = this.promptSelectTarget.value

    let outputSchema: object | null = null
    const rawSchema = this.outputSchemaFieldTarget.value.trim()
    if (rawSchema) {
      try { outputSchema = JSON.parse(rawSchema) } catch { /* leave null */ }
    }

    const response = await fetch(this.forkPromptUrlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": token,
      },
      body: JSON.stringify({
        based_on_prompt_id: promptId,
        system_prompt:      this.systemPromptFieldTarget.value,
        user_prompt:        this.userPromptFieldTarget.value,
        output_schema:      outputSchema,
      }),
    })

    if (response.ok) {
      const { id, version } = (await response.json()) as { id: number; version: number }
      const opt = document.createElement("option")
      opt.value = String(id)
      opt.textContent = `v${version} (edited)`
      this.promptSelectTarget.appendChild(opt)
      this.promptSelectTarget.value = String(id)
      this.closeEditPanel()
      this.contentLoaded = false
      ;(this.element as HTMLFormElement).requestSubmit()
    } else {
      if (submitButton) {
        submitButton.disabled = false
        submitButton.textContent = originalText
      }
    }
  }
}
