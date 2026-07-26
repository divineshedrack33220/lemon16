package repository

import (
	"context"

	"coded/models"

	"go.mongodb.org/mongo-driver/mongo"
)

type PostRepository struct {
	coll *mongo.Collection
}

func (r *PostRepository) Create(ctx context.Context, post *models.Post) error {
	_, err := r.coll.InsertOne(ctx, post)
	return err
}

func (r *PostRepository) Aggregate(ctx context.Context, pipeline mongo.Pipeline) (*mongo.Cursor, error) {
	return r.coll.Aggregate(ctx, pipeline)
}

func (r *PostRepository) Collection() *mongo.Collection {
	return r.coll
}
