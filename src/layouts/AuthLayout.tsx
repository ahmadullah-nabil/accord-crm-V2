// src/layouts/AuthLayout.tsx
// Centred card layout for /login. No sidebar. No topbar.
import { Outlet } from 'react-router-dom';

export function AuthLayout() {
  return (
    <div className="min-h-screen bg-gray-50 flex flex-col items-center justify-center p-4">
      <div className="w-full max-w-sm">
        <div className="text-center mb-8">
          <h1 className="text-2xl font-bold text-[#1E3A5F]">Accord CRM</h1>
          <p className="text-sm text-gray-500 mt-1">Accord Technologies Limited</p>
        </div>
        <div className="bg-white rounded-xl shadow-md p-8">
          <Outlet />
        </div>
      </div>
    </div>
  );
}
