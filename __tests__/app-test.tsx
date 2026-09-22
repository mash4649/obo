import { render } from '@testing-library/react-native';

import App from '../App';

describe('App', () => {
  it('requires authentication before opening the product path', async () => {
    const screen = await render(<App />);

    expect(screen.getByText('OBO')).toBeTruthy();
    expect(screen.getByText('事前登録済みのメールアドレスで認証してください。')).toBeTruthy();
    expect(screen.getByLabelText('メールアドレス')).toBeTruthy();
  });
});
