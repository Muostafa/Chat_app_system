import { ApplicationManager } from '@/components/ApplicationManager';
import { ChatManager } from '@/components/ChatManager';
import { MessageManager } from '@/components/MessageManager';
import { PerformanceChart } from '@/components/PerformanceChart';
import { ServiceToggle } from '@/components/ServiceToggle';
import { Activity } from 'lucide-react';

const Index = () => {
  return (
    <div className="min-h-screen bg-background">
      {/* Header */}
      <header className="border-b bg-card/50 backdrop-blur supports-[backdrop-filter]:bg-card/30">
        <div className="container mx-auto px-4 py-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <div className="h-10 w-10 rounded-lg bg-gradient-to-br from-primary to-accent flex items-center justify-center">
                <Activity className="h-6 w-6 text-primary-foreground" />
              </div>
              <div>
                <h1 className="text-2xl font-bold">Chat System Performance</h1>
                <p className="text-sm text-muted-foreground">Rails vs Go Comparison Dashboard</p>
              </div>
            </div>
            <ServiceToggle />
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="container mx-auto px-4 py-8">
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Left Sidebar - Applications & Chats */}
          <div className="lg:col-span-1 space-y-6">
            <ApplicationManager />
            <ChatManager />
          </div>

          {/* Main Content - Messages & Performance */}
          <div className="lg:col-span-2 space-y-6">
            <MessageManager />
            <PerformanceChart />
          </div>
        </div>
      </main>
    </div>
  );
};

export default Index;
