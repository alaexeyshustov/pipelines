import { Controller } from '@hotwired/stimulus';

export default class PromptCompareController extends Controller {
  static targets = ['checkbox', 'compareLink'];
  static values = { compareUrl: String };

  declare checkboxTargets: HTMLInputElement[];
  declare compareLinkTarget: HTMLAnchorElement;
  declare compareUrlValue: string;

  toggle() {
    const checked = this.checkboxTargets.filter((cb) => cb.checked);

    this.checkboxTargets.forEach((cb) => {
      if (!cb.checked) cb.disabled = checked.length >= 2;
    });

    if (checked.length === 2) {
      const url = new URL(this.compareUrlValue, window.location.origin);
      url.searchParams.set('prompt_a_id', checked[0].value);
      url.searchParams.set('prompt_b_id', checked[1].value);
      this.compareLinkTarget.href = url.toString();
      this.compareLinkTarget.classList.remove(
        'opacity-50',
        'pointer-events-none',
      );
      this.compareLinkTarget.removeAttribute('aria-disabled');
    } else {
      this.compareLinkTarget.href = '#';
      this.compareLinkTarget.classList.add('opacity-50', 'pointer-events-none');
      this.compareLinkTarget.setAttribute('aria-disabled', 'true');
    }
  }
}
