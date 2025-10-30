import { create } from 'zustand';
import { ServiceType, PerformanceMetric } from '@/lib/api';

interface StoreState {
  service: ServiceType;
  setService: (service: ServiceType) => void;
  
  selectedToken: string | null;
  setSelectedToken: (token: string | null) => void;
  
  selectedChat: number | null;
  setSelectedChat: (chatNumber: number | null) => void;
  
  metrics: PerformanceMetric[];
  addMetric: (metric: PerformanceMetric) => void;
  clearMetrics: () => void;
}

export const useStore = create<StoreState>((set) => ({
  service: 'rails',
  setService: (service) => set({ service }),
  
  selectedToken: null,
  setSelectedToken: (token) => set({ selectedToken: token }),
  
  selectedChat: null,
  setSelectedChat: (chatNumber) => set({ selectedChat: chatNumber }),
  
  metrics: [],
  addMetric: (metric) => set((state) => ({ 
    metrics: [...state.metrics.slice(-49), metric] // Keep last 50 metrics
  })),
  clearMetrics: () => set({ metrics: [] }),
}));
