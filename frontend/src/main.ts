import { mount } from 'svelte';

import App from './App.svelte';
import './styles.css';

const target = document.querySelector<HTMLDivElement>('#app');
if (target === null) {
  throw new Error('Missing #app element.');
}

mount(App, { target });
