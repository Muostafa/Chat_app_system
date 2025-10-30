import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { api } from '@/lib/api';
import { useStore } from '@/store/useStore';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { toast } from 'sonner';
import { Plus, MessageSquare } from 'lucide-react';

export const ChatManager = () => {
  const { service, addMetric, selectedToken, selectedChat, setSelectedChat } = useStore();
  const queryClient = useQueryClient();

  const { data: chats, isLoading } = useQuery({
    queryKey: ['chats', service, selectedToken],
    queryFn: async () => {
      if (!selectedToken) return [];
      const result = await api.listChats(service, selectedToken);
      addMetric(result.metric);
      return result.data;
    },
    enabled: !!selectedToken,
  });

  const createMutation = useMutation({
    mutationFn: async () => {
      if (!selectedToken) throw new Error('No application selected');
      const result = await api.createChat(service, selectedToken);
      addMetric(result.metric);
      return result.data;
    },
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ['chats'] });
      toast.success(`Chat #${data.number} created via ${service.toUpperCase()}`, {
        description: `Response time: ${Math.round(performance.now())}ms`,
      });
    },
    onError: () => {
      toast.error('Failed to create chat');
    },
  });

  if (!selectedToken) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Chats</CardTitle>
          <CardDescription>Select an application to manage chats</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="text-sm text-muted-foreground text-center py-8">
            Select an application from the list above
          </div>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Chats</CardTitle>
        <CardDescription>Create and manage chats for selected application</CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <Button
          onClick={() => createMutation.mutate()}
          disabled={createMutation.isPending}
          className="w-full"
        >
          <Plus className="mr-2 h-4 w-4" />
          Create New Chat
        </Button>

        <div className="space-y-2">
          {isLoading ? (
            <div className="text-sm text-muted-foreground">Loading chats...</div>
          ) : chats?.length === 0 ? (
            <div className="text-sm text-muted-foreground">No chats yet. Create one above!</div>
          ) : (
            chats?.map((chat) => (
              <div
                key={chat.number}
                className={`p-3 rounded-lg border bg-card cursor-pointer transition-all hover:border-primary ${
                  selectedChat === chat.number ? 'border-primary ring-2 ring-primary/20' : ''
                }`}
                onClick={() => setSelectedChat(chat.number)}
              >
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <MessageSquare className="h-4 w-4 text-muted-foreground" />
                    <span className="font-medium">Chat #{chat.number}</span>
                  </div>
                  <Badge variant="secondary">{chat.messages_count} messages</Badge>
                </div>
              </div>
            ))
          )}
        </div>
      </CardContent>
    </Card>
  );
};
