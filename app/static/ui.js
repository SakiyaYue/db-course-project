/* Shared progressive enhancement. Server permissions and validation remain authoritative. */
document.addEventListener('DOMContentLoaded', () => {
  for (const table of document.querySelectorAll('table.table')) {
    if (!table.parentElement.classList.contains('table-scroll')) {
      const wrapper = document.createElement('div'); wrapper.className = 'table-scroll';
      table.before(wrapper); wrapper.append(table);
    }
  }
  for (const button of document.querySelectorAll('[data-back]')) {
    button.addEventListener('click', () => history.length > 1 ? history.back() : location.assign('/'));
  }
  for (const form of document.forms) {
    form.addEventListener('input', () => {
      for (const field of form.querySelectorAll('input,select')) field.setCustomValidity('');
    });
    form.addEventListener('submit', event => {
      const fields = form.elements;
      for (const field of form.querySelectorAll('input[type=text][required]')) {
        if (!field.value.trim()) field.setCustomValidity('请填写此项，不能只输入空格。');
      }
      const start = fields.namedItem('start_time') || fields.namedItem('date_from');
      const end = fields.namedItem('end_time') || fields.namedItem('date_to');
      if (start && end && start.value && end.value &&
          (start.value > end.value || (start.name === 'start_time' && start.value === end.value))) {
        end.setCustomValidity('请检查开始和结束时间的先后顺序。');
      }
      if (fields.namedItem('operation')?.value === '补库' && Number(fields.namedItem('amount')?.value) <= 0) {
        fields.namedItem('amount').setCustomValidity('补库数量必须大于零。');
      }
      if (!form.reportValidity()) { event.preventDefault(); return; }
      if (event.defaultPrevented) return;
      if (form.dataset.confirm && !confirm(form.dataset.confirm)) { event.preventDefault(); return; }
      if (form.method.toLowerCase() === 'post') {
        if (form.dataset.submitting) { event.preventDefault(); return; }
        form.dataset.submitting = '1';
        for (const button of form.querySelectorAll('button[type=submit]')) button.disabled = true;
        form.setAttribute('aria-busy', 'true');
      }
    });
  }
});
window.addEventListener('pageshow', () => {
  for (const form of document.forms) {
    delete form.dataset.submitting; form.removeAttribute('aria-busy');
    for (const button of form.querySelectorAll('button[type=submit]')) button.disabled = false;
  }
});
