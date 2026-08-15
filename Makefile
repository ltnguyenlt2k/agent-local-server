.PHONY: up down logs preflight render-config status key list-keys revoke-key rotate-key backup restore smoke-local smoke-public cloudflare-setup

up:
	docker compose pull
	docker compose up -d

down:
	docker compose down

logs:
	docker compose logs -f

preflight:
	./scripts/preflight.sh

render-config:
	./scripts/render-config.sh

status:
	./scripts/status.sh

key:
	./scripts/create-api-key.sh $(NAME)

list-keys:
	./scripts/list-keys.sh

revoke-key:
	./scripts/revoke-key.sh $(KEY)

rotate-key:
	./scripts/rotate-key.sh $(NAME)

backup:
	./scripts/backup-db.sh

restore:
	./scripts/restore-db.sh $(FILE)

smoke-local:
	./scripts/smoke-test-local.sh

smoke-public:
	./scripts/smoke-test-public.sh

cloudflare-setup:
	./scripts/cloudflare-setup.sh $(NAME) $(HOSTNAME)
