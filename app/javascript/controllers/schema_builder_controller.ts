import { Controller } from '@hotwired/stimulus';

export default class SchemaBuilderController extends Controller {
  static targets = [
    'json',
    'schemaData',
    'rawEditor',
    'builderView',
    'rawView',
    'rawToggleBtn',
  ];

  declare jsonTarget: HTMLInputElement;
  declare schemaDataTarget: HTMLInputElement;
  declare rawEditorTarget: HTMLTextAreaElement;
  declare builderViewTarget: HTMLElement;
  declare rawViewTarget: HTMLElement;
  declare rawToggleBtnTarget: HTMLButtonElement;
  declare hasJsonTarget: boolean;
  declare hasRawEditorTarget: boolean;
  declare hasBuilderViewTarget: boolean;
  declare hasRawViewTarget: boolean;
  declare hasRawToggleBtnTarget: boolean;

  private showingRaw = false;

  // Stimulus calls this when schemaData target connects (including after Turbo Frame updates)
  schemaDataTargetConnected(element: HTMLInputElement) {
    if (this.hasJsonTarget) {
      this.jsonTarget.value = element.value;
    }
    if (this.hasRawEditorTarget) {
      this.rawEditorTarget.value = this.prettyJson(element.value);
    }
  }

  toggleRaw() {
    this.showingRaw = !this.showingRaw;
    if (this.hasBuilderViewTarget) {
      this.builderViewTarget.style.display = this.showingRaw ? 'none' : '';
    }
    if (this.hasRawViewTarget) {
      this.rawViewTarget.style.display = this.showingRaw ? '' : 'none';
      if (this.showingRaw && this.hasJsonTarget) {
        this.rawEditorTarget.value = this.prettyJson(this.jsonTarget.value);
      }
    }
    if (this.hasRawToggleBtnTarget) {
      this.rawToggleBtnTarget.textContent = this.showingRaw
        ? '← Builder'
        : 'Raw JSON';
    }
  }

  applyRaw() {
    const json = this.rawEditorTarget.value.trim();
    if (!json) return;

    const form = this.rawEditorTarget.closest('form') as HTMLFormElement | null;
    if (!form) return;

    const input = form.querySelector(
      "input[name='json']",
    ) as HTMLInputElement | null;
    if (input) input.value = json;

    // Exit raw mode only after a successful parse (200 response).
    // On 422, the frame renders the error and raw mode stays open so the user can fix the JSON.
    const frame = this.element.querySelector(
      'turbo-frame',
    ) as HTMLElement | null;
    if (frame) {
      const onRender = (event: Event) => {
        frame.removeEventListener('turbo:frame-render', onRender);
        const fetchResponse = (event as CustomEvent).detail?.fetchResponse as
          | { succeeded: boolean }
          | undefined;
        if (fetchResponse?.succeeded) {
          this.showingRaw = true; // currently true; toggleRaw will flip it to false
          this.toggleRaw();
        }
      };
      frame.addEventListener('turbo:frame-render', onRender);
    }

    form.requestSubmit();
  }

  private prettyJson(raw: string): string {
    try {
      return JSON.stringify(JSON.parse(raw), null, 2);
    } catch {
      return raw;
    }
  }
}
