import { Controller } from '@hotwired/stimulus';

export default class ProviderFieldsController extends Controller {
  static targets = ['select', 'fields'];
  static values = { provider: String };

  declare selectTarget: HTMLSelectElement;
  declare fieldsTarget: HTMLElement;
  declare providerValue: string;

  toggle() {
    this.fieldsTarget.classList.toggle(
      'hidden',
      this.selectTarget.value !== this.providerValue,
    );
  }
}
