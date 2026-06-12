import { Controller } from '@hotwired/stimulus';

export default class AccordionController extends Controller {
  static targets = ['details'];

  declare detailsTargets: HTMLDetailsElement[];
  private boundToggle!: (event: Event) => void;

  toggle(event: Event) {
    const opened = event.target as HTMLDetailsElement;
    this.detailsTargets.forEach((details) => {
      if (details !== opened) details.removeAttribute('open');
    });
  }

  connect() {
    this.boundToggle = this.toggle.bind(this);
    this.detailsTargets.forEach((details) => {
      details.addEventListener('toggle', this.boundToggle);
    });
  }

  disconnect() {
    this.detailsTargets.forEach((details) => {
      details.removeEventListener('toggle', this.boundToggle);
    });
  }
}
