// src/stores/ui.store.ts
// Global UI state: sidebar, modals, drawers.
// Never holds server data — that belongs to React Query.
import { create } from 'zustand';

interface UiState {
  sidebarOpen: boolean;
  activeDrawer: 'preview' | 'settings' | null;
  drawerDealId: string | null;
  activeModal: string | null;
  lastPipelineFilters: string | null; // Serialised URLSearchParams string

  toggleSidebar: () => void;
  setSidebarOpen: (open: boolean) => void;
  openDrawer: (type: 'preview' | 'settings', dealId?: string) => void;
  closeDrawer: () => void;
  openModal: (modalId: string) => void;
  closeModal: () => void;
  savePipelineFilters: (params: string) => void;
}

export const useUiStore = create<UiState>()((set) => ({
  sidebarOpen: true,
  activeDrawer: null,
  drawerDealId: null,
  activeModal: null,
  lastPipelineFilters: null,

  toggleSidebar: () => set((s) => ({ sidebarOpen: !s.sidebarOpen })),
  setSidebarOpen: (open) => set({ sidebarOpen: open }),
  openDrawer: (type, dealId) => set({ activeDrawer: type, drawerDealId: dealId ?? null }),
  closeDrawer: () => set({ activeDrawer: null, drawerDealId: null }),
  openModal: (modalId) => set({ activeModal: modalId }),
  closeModal: () => set({ activeModal: null }),
  savePipelineFilters: (params) => set({ lastPipelineFilters: params }),
}));
