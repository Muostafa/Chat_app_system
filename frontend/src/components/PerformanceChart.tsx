import { useStore } from '@/store/useStore';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';
import { TrendingDown } from 'lucide-react';

export const PerformanceChart = () => {
  const { metrics } = useStore();

  // Only compare endpoints that Go actually supports
  const GO_SUPPORTED_ENDPOINTS = ['create_chat', 'create_message'];

  // Filter to only show metrics for operations both services support
  const comparableMetrics = metrics.filter(m =>
    GO_SUPPORTED_ENDPOINTS.includes(m.endpoint)
  );

  // Helper to format endpoint names for display
  const formatEndpointName = (endpoint: string): string => {
    const names: Record<string, string> = {
      create_chat: 'Create Chat',
      create_message: 'Create Message',
    };
    return names[endpoint] || endpoint;
  };

  // Group metrics by endpoint and calculate averages
  const chartData = comparableMetrics.reduce((acc, metric, index) => {
    const displayName = formatEndpointName(metric.endpoint);
    const existingEndpoint = acc.find(item => item.name === displayName);
    if (existingEndpoint) {
      if (metric.service === 'rails') {
        existingEndpoint.rails = metric.duration;
      } else {
        existingEndpoint.go = metric.duration;
      }
    } else {
      acc.push({
        name: displayName,
        index,
        rails: metric.service === 'rails' ? metric.duration : undefined,
        go: metric.service === 'go' ? metric.duration : undefined,
      });
    }
    return acc;
  }, [] as Array<{ name: string; index: number; rails?: number; go?: number }>);

  // Calculate averages only for comparable operations
  const railsMetrics = comparableMetrics.filter(m => m.service === 'rails');
  const goMetrics = comparableMetrics.filter(m => m.service === 'go');

  const avgRails = railsMetrics.length > 0
    ? railsMetrics.reduce((sum, m) => sum + m.duration, 0) / railsMetrics.length
    : 0;
  const avgGo = goMetrics.length > 0
    ? goMetrics.reduce((sum, m) => sum + m.duration, 0) / goMetrics.length
    : 0;

  const improvement = avgRails > 0 && avgGo > 0
    ? ((avgRails - avgGo) / avgRails * 100).toFixed(1)
    : 0;

  return (
    <Card>
      <CardHeader>
        <CardTitle>Performance Comparison</CardTitle>
        <CardDescription>
          Comparing Rails vs Go for write operations (create chat & create message)
        </CardDescription>
      </CardHeader>
      <CardContent>
        {comparableMetrics.length === 0 ? (
          <div className="text-center py-12 text-muted-foreground">
            <TrendingDown className="h-12 w-12 mx-auto mb-4 opacity-50" />
            <p className="mb-2">No comparable performance data yet.</p>
            <p className="text-sm">
              Create chats or send messages using both Rails and Go services to see the comparison!
            </p>
          </div>
        ) : (
          <>
            <div className="grid grid-cols-3 gap-4 mb-6">
              <div className="text-center p-4 rounded-lg bg-rails/10 border border-rails/20">
                <div className="text-sm text-muted-foreground mb-1">Rails Avg (writes)</div>
                <div className="text-2xl font-bold text-rails">
                  {avgRails > 0 ? `${avgRails.toFixed(1)}ms` : 'N/A'}
                </div>
                <div className="text-xs text-muted-foreground mt-1">
                  {railsMetrics.length} operations
                </div>
              </div>
              <div className="text-center p-4 rounded-lg bg-go/10 border border-go/20">
                <div className="text-sm text-muted-foreground mb-1">Go Avg (writes)</div>
                <div className="text-2xl font-bold text-go">
                  {avgGo > 0 ? `${avgGo.toFixed(1)}ms` : 'N/A'}
                </div>
                <div className="text-xs text-muted-foreground mt-1">
                  {goMetrics.length} operations
                </div>
              </div>
              <div className="text-center p-4 rounded-lg bg-accent/10 border border-accent/20">
                <div className="text-sm text-muted-foreground mb-1">Go Improvement</div>
                <div className="text-2xl font-bold text-accent">
                  {avgRails > 0 && avgGo > 0 ? `${improvement}%` : 'N/A'}
                </div>
                <div className="text-xs text-muted-foreground mt-1">
                  faster writes
                </div>
              </div>
            </div>

            <ResponsiveContainer width="100%" height={300}>
              <LineChart data={chartData}>
                <CartesianGrid strokeDasharray="3 3" className="stroke-muted" />
                <XAxis 
                  dataKey="name" 
                  className="text-xs"
                  tick={{ fill: 'hsl(var(--muted-foreground))' }}
                />
                <YAxis 
                  label={{ value: 'Response Time (ms)', angle: -90, position: 'insideLeft' }}
                  tick={{ fill: 'hsl(var(--muted-foreground))' }}
                />
                <Tooltip 
                  contentStyle={{ 
                    backgroundColor: 'hsl(var(--card))',
                    border: '1px solid hsl(var(--border))',
                    borderRadius: '8px'
                  }}
                />
                <Legend />
                <Line 
                  type="monotone" 
                  dataKey="rails" 
                  stroke="hsl(var(--rails-service))" 
                  strokeWidth={2}
                  name="Rails"
                  connectNulls
                />
                <Line 
                  type="monotone" 
                  dataKey="go" 
                  stroke="hsl(var(--go-service))" 
                  strokeWidth={2}
                  name="Go"
                  connectNulls
                />
              </LineChart>
            </ResponsiveContainer>
          </>
        )}
      </CardContent>
    </Card>
  );
};
