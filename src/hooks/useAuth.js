import { useEffect } from 'react';
import { useAuthStore } from '../store/authStore';

export function useAuth() {
  const store = useAuthStore();
  
  useEffect(() => {
    store.init();
  }, []);

  return store;
}
