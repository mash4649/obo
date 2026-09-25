import { act, render } from '@testing-library/react-native';
import * as ScreenCapture from 'expo-screen-capture';
import { AppState, Platform } from 'react-native';

import App from '../App';

describe('App', () => {
  it('requires authentication before opening the product path', async () => {
    const screen = await render(<App />);

    expect(screen.getByText('OBO')).toBeTruthy();
    expect(screen.getByText('事前登録済みのメールアドレスで認証してください。')).toBeTruthy();
    expect(screen.getByLabelText('メールアドレス')).toBeTruthy();
  });

  it('covers private content when the app leaves the foreground', async () => {
    let change: ((state: 'background') => void) | undefined;
    const listener = jest.spyOn(AppState, 'addEventListener').mockImplementation((type, callback) => {
      if (type === 'change') change = callback as typeof change;
      return { remove: jest.fn() } as ReturnType<typeof AppState.addEventListener>;
    });
    const screen = await render(<App />);
    await act(() => change?.('background'));
    expect(screen.getByLabelText('非表示中')).toBeTruthy();
    await screen.unmount();
    listener.mockRestore();
  });

  it('keeps private content covered when app switcher protection fails', async () => {
    const originalOS = Object.getOwnPropertyDescriptor(Platform, 'OS');
    Object.defineProperty(Platform, 'OS', { configurable: true, value: 'ios' });
    const listener = jest.spyOn(AppState, 'addEventListener')
      .mockReturnValue({ remove: jest.fn() } as ReturnType<typeof AppState.addEventListener>);
    const protection = jest.spyOn(ScreenCapture, 'enableAppSwitcherProtectionAsync')
      .mockRejectedValue(new Error('synthetic failure'));
    try {
      const screen = await render(<App />);
      expect(await screen.findByText('安全な表示を開始できませんでした。')).toBeTruthy();
      expect(screen.getByLabelText('非表示中')).toBeTruthy();
      await screen.unmount();
    } finally {
      protection.mockRestore();
      listener.mockRestore();
      if (originalOS) Object.defineProperty(Platform, 'OS', originalOS);
    }
  });
});
