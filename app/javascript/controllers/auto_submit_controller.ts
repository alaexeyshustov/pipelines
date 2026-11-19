import { Controller } from '@hotwired/stimulus';

export default class AutoSubmitController extends Controller {
  submit(event: Event) {
    const target = event.currentTarget as HTMLElement | null;
    const form =
      (target as HTMLInputElement | null)?.form ?? target?.closest('form');
    form?.requestSubmit();
  }
}
