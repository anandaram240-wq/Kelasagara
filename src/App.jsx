// src/App.jsx — Main app router (complete)
import { useEffect } from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { ToastProvider } from './components/Toast';
import ProtectedRoute from './components/ProtectedRoute';
import { useAuthStore } from './store/authStore';

// Pages
import Home            from './pages/Home';
import Login           from './pages/Login';
import SetupProfile    from './pages/SetupProfile';
import WorkerDashboard from './pages/WorkerDashboard';
import HirerDashboard  from './pages/HirerDashboard';
import Chat            from './pages/Chat';
import FindJobs        from './pages/FindJobs';
import PostJob         from './pages/PostJob';
import Book            from './pages/Book';
import BookingDetail   from './pages/BookingDetail';
import Admin           from './pages/Admin';

const qc = new QueryClient({
  defaultOptions: { queries: { staleTime: 5 * 60 * 1000, retry: 1 } }
});

function AuthInit({ children }) {
  const init = useAuthStore(s => s.init);
  useEffect(() => { init(); }, []);
  return children;
}

export default function App() {
  return (
    <QueryClientProvider client={qc}>
      <ToastProvider>
        <BrowserRouter>
          <AuthInit>
            <Routes>
              {/* Public */}
              <Route path="/"      element={<Home />} />
              <Route path="/login" element={<Login />} />
              <Route path="/admin" element={<Admin />} />

              {/* Any logged-in user */}
              <Route path="/setup-profile"  element={<ProtectedRoute><SetupProfile /></ProtectedRoute>} />
              <Route path="/chat"           element={<ProtectedRoute><Chat /></ProtectedRoute>} />
              <Route path="/book"           element={<ProtectedRoute requiredRole="hirer"><Book /></ProtectedRoute>} />
              <Route path="/booking-detail" element={<ProtectedRoute><BookingDetail /></ProtectedRoute>} />

              {/* Worker */}
              <Route path="/worker-dashboard" element={<ProtectedRoute requiredRole="worker"><WorkerDashboard /></ProtectedRoute>} />
              <Route path="/find-jobs"        element={<ProtectedRoute requiredRole="worker"><FindJobs /></ProtectedRoute>} />

              {/* Hirer */}
              <Route path="/hirer-dashboard" element={<ProtectedRoute requiredRole="hirer"><HirerDashboard /></ProtectedRoute>} />
              <Route path="/post-job"        element={<ProtectedRoute requiredRole="hirer"><PostJob /></ProtectedRoute>} />

              {/* Fallback */}
              <Route path="*" element={<Navigate to="/" replace />} />
            </Routes>
          </AuthInit>
        </BrowserRouter>
      </ToastProvider>
    </QueryClientProvider>
  );
}
