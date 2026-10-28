// Preview routes served by ViewComponent (spec/components/previews). All data is fake and inline.
export const primitives = [
  'button',
  'badge',
  'alert',
  'card',
  'input',
  'label',
  'textarea',
  'select',
  'checkbox',
  'switch',
  'tabs',
  'pagination',
  'breadcrumb',
  'separator',
  'progress',
  'form_field',
  'search_input',
  'data_table',
  'dialog',
  'sidebar',
];

export const pages = ['models_index', 'pipeline_show', 'agent_form'];

export const primitiveUrl = (name: string) =>
  `/rails/view_components/ui/${name}_component/default`;
export const pageUrl = (name: string) =>
  `/rails/view_components/pages/${name}/default`;
