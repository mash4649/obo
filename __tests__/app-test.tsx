import { render } from '@testing-library/react-native';

import App from '../App';

describe('App', () => {
  it('renders the product boundary', async () => {
    const screen = await render(<App />);

    expect(screen.getByText('OBO')).toBeTruthy();
    expect(screen.getByText('Private by default.')).toBeTruthy();
  });
});
