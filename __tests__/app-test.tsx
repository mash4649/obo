import { act, render } from '@testing-library/react-native';
import { AppState } from 'react-native';

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
    listener.mockRestore();
  });
});
