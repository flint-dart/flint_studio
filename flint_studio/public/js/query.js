const form = document.getElementById('query-form');
const sqlInput = document.getElementById('sql-input');
const resultBox = document.getElementById('query-result');
const profileInput = document.getElementById('profile-id');

if (form && sqlInput && resultBox) {
  const applyState = (state) => {
    resultBox.classList.remove('text-slate-200', 'text-emerald-300', 'text-rose-300');
    if (state === 'success') {
      resultBox.classList.add('text-emerald-300');
    } else if (state === 'error') {
      resultBox.classList.add('text-rose-300');
    } else {
      resultBox.classList.add('text-slate-200');
    }
  };

  form.addEventListener('submit', async (event) => {
    event.preventDefault();

    const sql = sqlInput.value.trim();
    if (!sql) {
      applyState('error');
      resultBox.textContent = 'Please provide an SQL statement.';
      return;
    }

    applyState('idle');
    resultBox.textContent = 'Running query...';

    try {
      const response = await fetch('/query', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          sql,
          profile_id: profileInput ? profileInput.value : '',
        }),
      });

      const payload = await response.json();
      applyState(response.ok && payload.ok ? 'success' : 'error');
      resultBox.textContent = JSON.stringify(payload, null, 2);
    } catch (error) {
      applyState('error');
      resultBox.textContent = `Request failed: ${error}`;
    }
  });
}
