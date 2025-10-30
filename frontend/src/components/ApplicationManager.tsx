import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { api, ChatApplication } from '@/lib/api';
import { useStore } from '@/store/useStore';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { toast } from 'sonner';
import { Plus, Copy, Check } from 'lucide-react';

export const ApplicationManager = () => {
  const { service, addMetric, selectedToken, setSelectedToken } = useStore();
  const [appName, setAppName] = useState('');
  const [copiedToken, setCopiedToken] = useState<string | null>(null);
  const queryClient = useQueryClient();

  const { data: applications, isLoading } = useQuery({
    queryKey: ['applications', service],
    queryFn: async () => {
      const result = await api.listApplications(service);
      addMetric(result.metric);
      return result.data;
    },
  });

  const createMutation = useMutation({
    mutationFn: async (name: string) => {
      const result = await api.createApplication(service, name);
      addMetric(result.metric);
      return result.data;
    },
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ['applications'] });
      toast.success(`Application created via ${service.toUpperCase()}`, {
        description: `Token: ${data.token}`,
      });
      setAppName('');
    },
    onError: () => {
      toast.error('Failed to create application');
    },
  });

  const handleCopyToken = (token: string) => {
    navigator.clipboard.writeText(token);
    setCopiedToken(token);
    setTimeout(() => setCopiedToken(null), 2000);
    toast.success('Token copied to clipboard');
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>Chat Applications</CardTitle>
        <CardDescription>Create and manage your chat applications</CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex gap-2">
          <Input
            placeholder="Application name..."
            value={appName}
            onChange={(e) => setAppName(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && appName && createMutation.mutate(appName)}
          />
          <Button
            onClick={() => appName && createMutation.mutate(appName)}
            disabled={!appName || createMutation.isPending}
          >
            <Plus className="mr-2 h-4 w-4" />
            Create
          </Button>
        </div>

        <div className="space-y-2">
          {isLoading ? (
            <div className="text-sm text-muted-foreground">Loading applications...</div>
          ) : applications?.length === 0 ? (
            <div className="text-sm text-muted-foreground">No applications yet. Create one above!</div>
          ) : (
            applications?.map((app) => (
              <div
                key={app.token}
                className={`p-3 rounded-lg border bg-card cursor-pointer transition-all hover:border-primary ${
                  selectedToken === app.token ? 'border-primary ring-2 ring-primary/20' : ''
                }`}
                onClick={() => setSelectedToken(app.token)}
              >
                <div className="flex items-start justify-between gap-2">
                  <div className="flex-1 min-w-0">
                    <div className="font-medium">{app.name}</div>
                    <div className="flex items-center gap-2 mt-1">
                      <code className="text-xs bg-muted px-2 py-1 rounded font-mono truncate">
                        {app.token}
                      </code>
                      <Button
                        size="sm"
                        variant="ghost"
                        className="h-6 w-6 p-0"
                        onClick={(e) => {
                          e.stopPropagation();
                          handleCopyToken(app.token);
                        }}
                      >
                        {copiedToken === app.token ? (
                          <Check className="h-3 w-3 text-accent" />
                        ) : (
                          <Copy className="h-3 w-3" />
                        )}
                      </Button>
                    </div>
                  </div>
                  <Badge variant="secondary">{app.chats_count} chats</Badge>
                </div>
              </div>
            ))
          )}
        </div>
      </CardContent>
    </Card>
  );
};
