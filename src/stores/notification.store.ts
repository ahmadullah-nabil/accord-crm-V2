// src/stores/notification.store.ts
// Toast notification queue. Every mutation success/error calls addToast().
import { create } from 'zustand';

export type ToastType = 'success' | 'error' | 'warning' | 'info';

export interface Toast {
  id: string;
  type: ToastType;
  message: string;
  duration: number; // ms
}

interface NotificationState {
  toasts: Toast[];
  addToast: (type: ToastType, message: string, duration?: number) => void;
  removeToast: (id: string) => void;
}

export const useNotificationStore = create<NotificationState>()((set) => ({
  toasts: [],

  addToast: (type, message, duration) => {
    const id = crypto.randomUUID();
    const ms = duration ?? (type === 'error' ? 8000 : 4000);
    set((s) => ({ toasts: [...s.toasts, { id, type, message, duration: ms }] }));
    // Auto-remove after duration
    setTimeout(() => {
      set((s) => ({ toasts: s.toasts.filter((t) => t.id !== id) }));
    }, ms);
  },

  removeToast: (id) =>
    set((s) => ({ toasts: s.toasts.filter((t) => t.id !== id) })),
}));
