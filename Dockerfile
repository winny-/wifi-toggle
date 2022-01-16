FROM racket/racket:8.3

RUN apt install -y --no-install-recommends openssh-client

WORKDIR /app
COPY info.rkt .
RUN raco pkg install --no-docs --auto --name wifi-toggle
COPY . .

ENTRYPOINT /app/entrypoint.sh
