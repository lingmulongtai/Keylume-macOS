import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import '@fontsource/ibm-plex-sans-jp/400.css';
import '@fontsource/ibm-plex-sans-jp/500.css';
import '@fontsource/ibm-plex-sans-jp/600.css';
import './styles.css';
import App from './App';
import { StageWindow, StageControls } from './stage/Stage';
import { isTauri } from '@tauri-apps/api/core';
import './mac-glass.css';
const surface = new URLSearchParams(location.search).get('view');
if (surface === 'stage' || surface === 'stage-controls')
  document.documentElement.dataset.surface = surface;
else if (isTauri()) document.documentElement.dataset.nativeGlass = 'true';
createRoot(document.getElementById('root')!).render(
  <StrictMode>
    {surface === 'stage' ? (
      <StageWindow />
    ) : surface === 'stage-controls' ? (
      <StageControls />
    ) : (
      <App />
    )}
  </StrictMode>,
);
