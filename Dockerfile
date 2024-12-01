FROM golang:1.23

# Install dependencies
RUN apt-get update && apt-get install -y unzip libc6
RUN apt-get clean

# Install protoc
RUN curl -OL https://github.com/protocolbuffers/protobuf/releases/download/v21.0/protoc-21.0-linux-x86_64.zip
RUN unzip protoc-21.0-linux-x86_64.zip -d /usr/local
RUN rm protoc-21.0-linux-x86_64.zip

# Install Go tools
RUN go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.28
RUN go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@v1.2
RUN go install github.com/grpc-ecosystem/grpc-gateway/v2/protoc-gen-grpc-gateway@v2.7.3
RUN go install github.com/grpc-ecosystem/grpc-gateway/v2/protoc-gen-openapiv2@v2.7.3
RUN go install github.com/favadi/protoc-go-inject-tag@latest
RUN go install github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen@v2.4.1
RUN go install github.com/99designs/gqlgen@latest
RUN go install github.com/go-task/task/v3/cmd/task@latest

# Install Google API Protos
RUN curl -OL https://github.com/googleapis/googleapis/archive/refs/heads/master.zip
RUN unzip master.zip -d /usr/local/include
RUN rm master.zip
