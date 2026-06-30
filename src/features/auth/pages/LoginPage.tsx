// src/features/auth/pages/LoginPage.tsx
import { LoginForm } from '../components/LoginForm';

export function LoginPage() {
  return (
    <>
      <h2 className="text-lg font-semibold text-gray-900 mb-6">Sign in to your account</h2>
      <LoginForm />
    </>
  );
}
