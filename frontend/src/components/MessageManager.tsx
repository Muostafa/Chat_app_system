import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { api } from "@/lib/api";
import { useStore } from "@/store/useStore";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { toast } from "sonner";
import { Plus, Search } from "lucide-react";

export const MessageManager = () => {
  const { service, addMetric, selectedToken, selectedChat } = useStore();
  const [messageBody, setMessageBody] = useState("");
  const [searchQuery, setSearchQuery] = useState("");
  const queryClient = useQueryClient();

  const { data: messages, isLoading } = useQuery({
    queryKey: ["messages", service, selectedToken, selectedChat, searchQuery],
    queryFn: async () => {
      if (!selectedToken || !selectedChat) return [];

      if (searchQuery) {
        const result = await api.searchMessages(
          service,
          selectedToken,
          selectedChat,
          searchQuery
        );
        addMetric(result.metric);
        return result.data;
      } else {
        const result = await api.listMessages(
          service,
          selectedToken,
          selectedChat
        );
        addMetric(result.metric);
        return result.data;
      }
    },
    enabled: !!selectedToken && !!selectedChat,
  });

  const createMutation = useMutation({
    mutationFn: async (body: string) => {
      if (!selectedToken || !selectedChat) throw new Error("No chat selected");
      const result = await api.createMessage(
        service,
        selectedToken,
        selectedChat,
        body
      );
      addMetric(result.metric);
      return result.data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["messages"] });
      queryClient.invalidateQueries({ queryKey: ["chats"] });
      toast.success(`Message sent via ${service.toUpperCase()}`);
      setMessageBody("");
    },
    onError: () => {
      toast.error("Failed to send message");
    },
  });

  if (!selectedToken || !selectedChat) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Messages</CardTitle>
          <CardDescription>
            Select a chat to view and send messages
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="text-sm text-muted-foreground text-center py-8">
            Select a chat from the list above
          </div>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card className="flex flex-col">
      <CardHeader>
        <CardTitle>Messages - Chat #{selectedChat}</CardTitle>
        <CardDescription>Send and search messages</CardDescription>
      </CardHeader>
      <CardContent className="flex-1 flex flex-col space-y-4">
        <div className="flex gap-2">
          <div className="relative flex-1">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
            <Input
              placeholder="Search messages..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="pl-9"
            />
          </div>
        </div>

        <div className="flex-1 space-y-2 overflow-auto min-h-[200px] max-h-[400px] border rounded-lg p-4 bg-muted/20">
          {isLoading ? (
            <div className="text-sm text-muted-foreground">
              Loading messages...
            </div>
          ) : messages?.length === 0 ? (
            <div className="text-sm text-muted-foreground">
              {searchQuery
                ? "No messages found"
                : "No messages yet. Send one below!"}
            </div>
          ) : (
            messages?.map((message) => (
              <div
                key={message.number}
                className="p-3 rounded-lg bg-card border animate-in fade-in slide-in-from-bottom-2"
              >
                <div className="flex items-start gap-2">
                  <span className="text-xs text-muted-foreground font-mono">
                    #{message.number}
                  </span>
                  <p className="flex-1">{message.body}</p>
                </div>
              </div>
            ))
          )}
        </div>

        <div className="flex gap-2">
          <Input
            placeholder="Type your message..."
            value={messageBody}
            onChange={(e) => setMessageBody(e.target.value)}
            onKeyDown={(e) =>
              e.key === "Enter" &&
              messageBody &&
              createMutation.mutate(messageBody)
            }
          />
          <Button
            onClick={() => messageBody && createMutation.mutate(messageBody)}
            disabled={!messageBody || createMutation.isPending}
          >
            <Plus className="mr-2 h-4 w-4" />
            Send
          </Button>
        </div>
      </CardContent>
    </Card>
  );
};
