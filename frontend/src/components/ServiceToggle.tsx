import { useStore } from '@/store/useStore';
import { Button } from '@/components/ui/button';
import { Zap, Train } from 'lucide-react';

export const ServiceToggle = () => {
  const { service, setService } = useStore();

  return (
    <div className="flex gap-2 p-1 bg-muted rounded-lg">
      <Button
        variant={service === 'rails' ? 'default' : 'ghost'}
        size="sm"
        onClick={() => setService('rails')}
        className={service === 'rails' ? 'bg-rails hover:bg-rails/90' : ''}
      >
        <Train className="mr-2 h-4 w-4" />
        Rails
      </Button>
      <Button
        variant={service === 'go' ? 'default' : 'ghost'}
        size="sm"
        onClick={() => setService('go')}
        className={service === 'go' ? 'bg-go hover:bg-go/90' : ''}
      >
        <Zap className="mr-2 h-4 w-4" />
        Go
      </Button>
    </div>
  );
};
