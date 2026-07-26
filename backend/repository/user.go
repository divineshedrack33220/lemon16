package repository

import (
	"context"

	"coded/models"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

type UserRepository struct {
	coll *mongo.Collection
}

func (r *UserRepository) FindByID(ctx context.Context, id primitive.ObjectID) (*models.User, error) {
	var user models.User
	err := r.coll.FindOne(ctx, bson.M{"_id": id}).Decode(&user)
	if err != nil {
		return nil, err
	}
	return &user, nil
}

func (r *UserRepository) FindByEmail(ctx context.Context, email string) (*models.User, error) {
	var user models.User
	err := r.coll.FindOne(ctx, bson.M{"email": email}).Decode(&user)
	if err != nil {
		return nil, err
	}
	return &user, nil
}

func (r *UserRepository) FindByReferralCode(ctx context.Context, code string) (*models.User, error) {
	var user models.User
	err := r.coll.FindOne(ctx, bson.M{"referralCode": code}).Decode(&user)
	if err != nil {
		return nil, err
	}
	return &user, nil
}

func (r *UserRepository) Create(ctx context.Context, user *models.User) error {
	_, err := r.coll.InsertOne(ctx, user)
	return err
}

func (r *UserRepository) Update(ctx context.Context, id primitive.ObjectID, update bson.M) (*mongo.UpdateResult, error) {
	return r.coll.UpdateOne(ctx, bson.M{"_id": id}, update)
}

func (r *UserRepository) Delete(ctx context.Context, id primitive.ObjectID) error {
	_, err := r.coll.DeleteOne(ctx, bson.M{"_id": id})
	return err
}

func (r *UserRepository) CountByField(ctx context.Context, field string, value interface{}) (int64, error) {
	return r.coll.CountDocuments(ctx, bson.M{field: value})
}

func (r *UserRepository) Search(ctx context.Context, filter bson.M, limit int64) ([]models.User, error) {
	opts := options.Find().SetLimit(limit)
	cursor, err := r.coll.Find(ctx, filter, opts)
	if err != nil {
		return nil, err
	}
	defer cursor.Close(ctx)

	var users []models.User
	if err := cursor.All(ctx, &users); err != nil {
		return nil, err
	}
	return users, nil
}

func (r *UserRepository) FindMany(ctx context.Context, filter bson.M) ([]models.User, error) {
	cursor, err := r.coll.Find(ctx, filter)
	if err != nil {
		return nil, err
	}
	defer cursor.Close(ctx)

	var users []models.User
	if err := cursor.All(ctx, &users); err != nil {
		return nil, err
	}
	return users, nil
}

func (r *UserRepository) FindWithFilterAndLimit(ctx context.Context, filter bson.M, limit int64, opts ...*options.FindOptions) ([]models.User, error) {
	findOpts := options.Find().SetLimit(limit)
	for _, o := range opts {
		findOpts = o
	}
	cursor, err := r.coll.Find(ctx, filter, findOpts)
	if err != nil {
		return nil, err
	}
	defer cursor.Close(ctx)

	var users []models.User
	if err := cursor.All(ctx, &users); err != nil {
		return nil, err
	}
	return users, nil
}

func (r *UserRepository) Collection() *mongo.Collection {
	return r.coll
}
