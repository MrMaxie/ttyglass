const app = document.querySelector<HTMLDivElement>('#app');

if (app === null) {
  throw new Error('Missing #app element.');
}

app.textContent = 'ttyglass';
