package repository

import (
	"context"

	"coded/models"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

type FavoriteRepository struct {
	coll *mongo.Collection
}

func (r *FavoriteRepository) Exists(ctx context.Context, userID, targetID primitive.ObjectID) (bool, error) {
	count, err := r.coll.CountDocuments(ctx, bson.M{
		"userId":       userID,
		"targetUserId": targetID,
	})
	return count > 0, err
}

func (r *FavoriteRepository) Create(ctx context.Context, fav *models.Favorite) error {
	_, err := r.coll.InsertOne(ctx, fav)
	return err
}

func (r *FavoriteRepository) Delete(ctx context.Context, userID, targetID primitive.ObjectID) (*mongo.DeleteResult, error) {
	return r.coll.DeleteOne(ctx, bson.M{
		"userId":       userID,
		"targetUserId": targetID,
	})
}

func (r *FavoriteRepository) FindByUser(ctx context.Context, userID primitive.ObjectID, limit int64) ([]models.Favorite, error) {
	opts := options.Find().SetSort(bson.D{{Key: "createdAt", Value: -1}}).SetLimit(limit)
	cursor, err := r.coll.Find(ctx, bson.M{"userId": userID}, opts)
	if err != nil {
		return nil, err
	}
	defer cursor.Close(ctx)

	var favorites []models.Favorite
	if err := cursor.All(ctx, &favorites); err != nil {
		return nil, err
	}
	return favorites, nil
}

func (r *FavoriteRepository) Collection() *mongo.Collection {
	return r.coll
}
