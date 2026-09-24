import AsyncStorage from '@react-native-async-storage/async-storage';
import Constants from 'expo-constants';
import * as Crypto from 'expo-crypto';
import * as Notifications from 'expo-notifications';
import { Platform } from 'react-native';

import { registerPush, revokePush } from '../auth/command';

const INSTALLATION_KEY = 'obo:p1:push-installation-id';
const OPT_IN_KEY = 'obo:p1:push-opt-in';

export async function isPushOptedIn(): Promise<boolean> {
  return (await AsyncStorage.getItem(OPT_IN_KEY)) === 'true';
}

export async function enablePush(): Promise<void> {
  if (Platform.OS !== 'ios') throw new Error('P1 Push は iOS のみです。');
  const permission = await Notifications.requestPermissionsAsync();
  if (permission.ios?.status !== Notifications.IosAuthorizationStatus.AUTHORIZED) {
    throw new Error('通知が許可されていません。アプリ内で確認できます。');
  }
  const projectId = Constants.expoConfig?.extra?.eas?.projectId ?? Constants.easConfig?.projectId;
  if (!projectId) throw new Error('Push の設定がまだありません。アプリ内で確認できます。');
  const token = (await Notifications.getExpoPushTokenAsync({ projectId })).data;
  let id = await AsyncStorage.getItem(INSTALLATION_KEY);
  if (!id) {
    id = Crypto.randomUUID();
    await AsyncStorage.setItem(INSTALLATION_KEY, id);
  }
  await registerPush(id, token);
  await AsyncStorage.setItem(OPT_IN_KEY, 'true');
}

export async function disablePush(): Promise<void> {
  const id = await AsyncStorage.getItem(INSTALLATION_KEY);
  if (id) await revokePush(id);
  await AsyncStorage.multiRemove([INSTALLATION_KEY, OPT_IN_KEY]);
}

export async function checkPushPermission(): Promise<void> {
  if (!(await isPushOptedIn())) return;
  const permission = await Notifications.getPermissionsAsync();
  if (permission.ios?.status !== Notifications.IosAuthorizationStatus.AUTHORIZED) {
    await disablePush();
  } else {
    await enablePush();
  }
}

export async function clearPushPreference(): Promise<void> {
  await AsyncStorage.multiRemove([INSTALLATION_KEY, OPT_IN_KEY]);
}
