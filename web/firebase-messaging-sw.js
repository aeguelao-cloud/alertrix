/* eslint-disable no-undef */
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyCdaebCdME_g0QDjFYhysnQUpvEqlcmW3w',
  authDomain: 'alertrix-eb014.firebaseapp.com',
  projectId: 'alertrix-eb014',
  storageBucket: 'alertrix-eb014.firebasestorage.app',
  messagingSenderId: '509883742045',
  appId: '1:509883742045:web:a755fe97ce4aa0c5c99ab4',
  measurementId: 'G-MNQCLGVRXT',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const title = payload?.notification?.title || 'Alertrix Alert';
  const body = payload?.notification?.body || 'New incident detected';
  self.registration.showNotification(title, {
    body,
    icon: '/icons/Icon-192.png',
    data: payload?.data || {},
  });
});
